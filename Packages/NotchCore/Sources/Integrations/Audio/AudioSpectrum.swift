import Accelerate
import CoreAudio
import Foundation
import os

/// Müziğe tepki veren çubuklar için ses spektrumu. Sistem sesinin kopyası Core Audio süreç
/// dinleyicisinden (`CATapDescription`, macOS 14.2+) alınır, FFT ile dört banda (bas → tiz) bölünür.
///
/// İzin: ilk başlatmada macOS "Sistem sesi kaydı" izni ister (Info.plist `NSAudioCaptureUsageDescription`);
/// izin yoksa dinleyici sessizlik verir ve çubuklar yapay harekete döner. Ses hiçbir yere yazılmaz,
/// yalnız dört sayı çıkar. Kimse kullanmıyorsa (çubuk ekranda değil, müzik durdu) birkaç saniye
/// sonra dinleyici kapatılır; enerji yalnız çalarken ve çubuklar görünürken harcanır.
@MainActor
public final class AudioSpectrum {
    public let levels = SpectrumLevels()
    /// Son başlatma hatası (tanılama için); başarılıysa nil.
    public private(set) var lastError: String?
    public var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled, users > 0 { startIfNeeded() } else if !isEnabled { stopNow() }
        }
    }

    public var isRunning: Bool { session != nil }

    private var users = 0
    private var session: SpectrumSession?
    private var stopTask: Task<Void, Never>?
    private var outputListener: AudioObjectPropertyListenerBlock?
    /// Kısa bildirim çubukların yerini birkaç saniyeliğine alınca dinleyici yeniden kurulmasın.
    static let idleGrace: Duration = .seconds(5)

    public init() {}

    /// Çubuk görünür ve hareketliyken çağrılır; her `acquire` bir `release` ister.
    public func acquire() {
        users += 1
        stopTask?.cancel()
        stopTask = nil
        startIfNeeded()
    }

    public func release() {
        users = max(0, users - 1)
        guard users == 0, session != nil else { return }
        stopTask?.cancel()
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.idleGrace)
            guard let self, !Task.isCancelled, self.users == 0 else { return }
            self.stopNow()
        }
    }

    private func startIfNeeded() {
        guard isEnabled, session == nil else { return }
        guard #available(macOS 14.2, *) else {
            lastError = "macOS 14.2 gerekir"
            return
        }
        do {
            session = try TapSession(levels: levels)
            lastError = nil
            listenForOutputChanges()
        } catch {
            lastError = String(describing: error)
            levels.reset()
        }
    }

    private func stopNow() {
        stopTask?.cancel()
        stopTask = nil
        session?.stop()
        session = nil
        removeOutputListener()
        levels.reset()
    }

    /// Dinleyici o anki çıkış aygıtına bağlı kümede çalışır; çıkış değişince yeniden kurulur.
    private func listenForOutputChanges() {
        guard outputListener == nil else { return }
        var address = Self.outputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.session != nil else { return }
                self.session?.stop()
                self.session = nil
                self.startIfNeeded()
            }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            outputListener = block
        }
    }

    private func removeOutputListener() {
        guard let block = outputListener else { return }
        var address = Self.outputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        outputListener = nil
    }

    private static let outputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

/// Ses iş parçacığından yazılan, çizimden okunan son düzeyler (0…1). Kilitli, kopyalanarak okunur.
public final class SpectrumLevels: Sendable {
    public static let bandCount = 4
    /// Bu kadar süre sinyal yoksa çizim yapay harekete döner (izin yok ya da sessizlik).
    static let signalTimeout: CFTimeInterval = 1.2

    private struct State {
        var values = [Float](repeating: 0, count: SpectrumLevels.bandCount)
        var lastSignal: CFTimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func read(now: CFTimeInterval = CACurrentMediaTimeShim.now()) -> (values: [Float], hasSignal: Bool) {
        state.withLock { ($0.values, now - $0.lastSignal < Self.signalTimeout) }
    }

    func write(_ values: [Float], signal: Bool, now: CFTimeInterval = CACurrentMediaTimeShim.now()) {
        state.withLock {
            $0.values = values
            if signal { $0.lastSignal = now }
        }
    }

    func reset() {
        state.withLock { $0 = State() }
    }
}

/// QuartzCore'u bu modüle çekmeden monoton saat (CACurrentMediaTime ile aynı kaynak).
public enum CACurrentMediaTimeShim {
    public static func now() -> CFTimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }
}

enum SpectrumError: Error, CustomStringConvertible {
    case status(String, OSStatus)
    case noOutputDevice

    var description: String {
        switch self {
        case let .status(step, status): "\(step): \(status)"
        case .noOutputDevice: "çıkış aygıtı yok"
        }
    }
}

private protocol SpectrumSession: AnyObject {
    func stop()
}

/// Bir dinleyici + özel küme aygıtı + IO bloğu. Oluşturulunca çalışır, `stop` ile söner.
@available(macOS 14.2, *)
private final class TapSession: SpectrumSession {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.talatozcoban.notchmvp.spectrum", qos: .userInteractive)

    init(levels: SpectrumLevels) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "NotchMVP spektrum"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw SpectrumError.status("dinleyici", status) }

        do {
            let outputUID = try Self.defaultOutputUID()
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "NotchMVP spektrum",
                kAudioAggregateDeviceUIDKey: "com.talatozcoban.notchmvp.spectrum.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                                   kAudioSubTapUIDKey: description.uuid.uuidString]],
            ]
            status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
            guard status == noErr else { throw SpectrumError.status("küme aygıtı", status) }

            let format = Self.tapFormat(tapID)
            let analyzer = SpectrumAnalyzer(sampleRate: format?.mSampleRate ?? 48_000, output: levels)
            let isFloat = format.map { $0.mFormatFlags & kAudioFormatFlagIsFloat != 0 } ?? true
            status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
                guard isFloat else { return }
                analyzer.consume(input)
            }
            guard status == noErr, let procID else { throw SpectrumError.status("IO", status) }
            status = AudioDeviceStart(aggregateID, procID)
            guard status == noErr else { throw SpectrumError.status("başlatma", status) }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { throw SpectrumError.noOutputDevice }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr,
              let value = uid?.takeRetainedValue() else { throw SpectrumError.noOutputDevice }
        return value as String
    }

    private static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        return AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr ? format : nil
    }
}

/// Tek kanala indirir, 1024 örnekte bir FFT; dört bandın enerjisi kendi yakın geçmiş tepesine göre
/// ölçeklenir (ses düzeyinden bağımsız canlı hareket), hızlı yükselip yavaş iner.
/// Yalnız ses kuyruğunda çağrılır.
final class SpectrumAnalyzer: @unchecked Sendable {
    static let fftSize = 1024
    private static let log2n = vDSP_Length(10)
    /// Bant sınırları (Hz): bas, alt orta, üst orta, tiz.
    static let bandEdges: [Double] = [40, 160, 640, 2_500, 10_000]
    /// Tepe bu kadar dB altında çubuk sıfır. Müzikte vuruşlar arası fark 4–8 dB: 30 dB'de çubuklar
    /// hep tepede kalıyordu (2026-10-16 kare ölçümü).
    private static let dynamicRange: Float = 15
    /// Orta düzeyleri aşağı çeker; vuruş daha belirgin.
    private static let curve: Float = 1.4
    /// Tepe her FFT'de bu kadar dB iner (~47 FFT/sn → ~7 dB/sn).
    private static let peakDecay: Float = 0.15
    /// Bu RMS altı sessizlik (≈ −80 dBFS).
    private static let silence: Float = 1e-4

    private let setup: FFTSetup
    private let window: [Float]
    private var samples = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize)
    private var windowed = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize)
    private var filled = 0
    private var real = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize / 2)
    private var imaginary = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize / 2)
    private var power = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize / 2)
    private var peaks = [Float](repeating: -120, count: SpectrumLevels.bandCount)
    private var smoothed = [Float](repeating: 0, count: SpectrumLevels.bandCount)
    private let bins: [Range<Int>]
    private let output: SpectrumLevels

    init(sampleRate: Double, output: SpectrumLevels) {
        setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.fftSize, isHalfWindow: false)
        bins = Self.binRanges(sampleRate: sampleRate)
        self.output = output
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    static func binRanges(sampleRate: Double) -> [Range<Int>] {
        let binWidth = sampleRate / Double(fftSize)
        let maxBin = fftSize / 2
        return zip(bandEdges, bandEdges.dropFirst()).map { low, high in
            let start = max(1, Int((low / binWidth).rounded()))
            let end = min(maxBin, max(start + 1, Int((high / binWidth).rounded())))
            return start..<end
        }
    }

    func consume(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, first.mNumberChannels > 0 else { return }
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * Int(first.mNumberChannels))
        var frame = 0
        while frame < frames {
            let count = min(frames - frame, Self.fftSize - filled)
            mix(buffers, from: frame, count: count)
            filled += count
            frame += count
            if filled == Self.fftSize {
                analyze()
                filled = 0
            }
        }
    }

    /// Testler için: tek kanallı örnekler.
    func consume(mono: [Float]) {
        var frame = 0
        while frame < mono.count {
            let count = min(mono.count - frame, Self.fftSize - filled)
            for index in 0..<count { samples[filled + index] = mono[frame + index] }
            filled += count
            frame += count
            if filled == Self.fftSize {
                analyze()
                filled = 0
            }
        }
    }

    /// Tüm kanalların ortalaması `samples[filled...]` içine. Örnek başına Swift döngüsü yok: hata
    /// ayıklama derlemesinde bile vDSP (ölçüm 2026-10-16: döngülerle tek çekirdeğin %7'si).
    private func mix(_ buffers: UnsafeMutableAudioBufferListPointer, from start: Int, count: Int) {
        let offset = filled
        samples.withUnsafeMutableBufferPointer { output in
            let destination = output.baseAddress! + offset
            vDSP_vclr(destination, 1, vDSP_Length(count))
            var channelTotal = 0
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channels = Int(buffer.mNumberChannels)
                channelTotal += channels
                for channel in 0..<channels {
                    vDSP_vadd(data + start * channels + channel, vDSP_Stride(channels), destination, 1,
                              destination, 1, vDSP_Length(count))
                }
            }
            guard channelTotal > 1 else { return }
            var scale = 1 / Float(channelTotal)
            vDSP_vsmul(destination, 1, &scale, destination, 1, vDSP_Length(count))
        }
    }

    private func analyze() {
        let half = vDSP_Length(Self.fftSize / 2)
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(Self.fftSize))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(Self.fftSize))
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { pointer in
                    pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, half)
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                power.withUnsafeMutableBufferPointer {
                    vDSP_zvmags(&split, 1, $0.baseAddress!, 1, half)
                }
            }
        }
        let hasSignal = rms > Self.silence
        var values = [Float](repeating: 0, count: SpectrumLevels.bandCount)
        for (band, range) in bins.enumerated() {
            var target: Float = 0
            if hasSignal {
                var sum: Float = 0
                power.withUnsafeBufferPointer {
                    vDSP_sve($0.baseAddress! + range.lowerBound, 1, &sum, vDSP_Length(range.count))
                }
                let mean = sum / Float(range.count)
                let decibels = 10 * log10(mean + 1e-12)
                peaks[band] = max(decibels, peaks[band] - Self.peakDecay)
                target = pow(max(0, min(1, 1 - (peaks[band] - decibels) / Self.dynamicRange)), Self.curve)
            }
            // Hızlı yükselir, yavaş iner.
            let rate: Float = target > smoothed[band] ? 0.6 : 0.3
            smoothed[band] += (target - smoothed[band]) * rate
            values[band] = smoothed[band]
        }
        output.write(values, signal: hasSignal)
    }
}
