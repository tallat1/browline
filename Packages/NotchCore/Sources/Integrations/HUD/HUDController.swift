import AppKit
import ApplicationServices
import CoreAudio
import Observation
import PrivateBridges

/// Ses ve parlaklık göstergesi.
/// - `overlay`: CoreAudio değişikliklerini dinler, notch'ta gösterir; sistem HUD'ı da görünür. İzin istemez.
/// - `replace`: medya tuşlarını aktif tap ile yutar, sesi/parlaklığı kendisi ayarlar; sistem HUD'ı çizilmez.
///   Erişilebilirlik izni ister. SIGSTOP gibi sistem süreçlerine dokunan yollar kullanılmaz.
@MainActor
@Observable
public final class HUDController {
    public enum Mode: String, CaseIterable, Sendable {
        case off
        case overlay
        case replace
    }

    public enum Kind: Equatable, Sendable {
        case volume
        case brightness
    }

    public private(set) var mode: Mode = .off
    public private(set) var kind: Kind = .volume
    /// 0…1
    public private(set) var level: Double = 0
    public private(set) var isMuted = false
    /// `replace` modunda tap gerçekten kurulu mu (izin yoksa false).
    public private(set) var isTapActive = false

    @ObservationIgnored public var onShow: (() -> Void)?
    @ObservationIgnored private let tap = MediaKeyTap()
    @ObservationIgnored private var volumeListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    /// Bir ses değişiminde dinleyici kanal başına birkaç kez çağrılır; okuma bir kez yapılır.
    @ObservationIgnored private var volumeReadPending = false
    @ObservationIgnored private var trustObserver: NSObjectProtocol?

    nonisolated static let step = 1.0 / 16
    nonisolated static let fineStep = 1.0 / 64

    public init() {
        tap.handler = { [weak self] key, _, fine in self?.handle(key, fine: fine) ?? false }
    }

    public static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    public var isBrightnessAvailable: Bool { DisplayBrightness.isAvailable && Self.builtInDisplay() != nil }

    public func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        tearDown()
        mode = newMode
        switch newMode {
        case .off:
            break
        case .overlay:
            installVolumeListeners()
        case .replace:
            startTap()
        }
    }

    // MARK: - replace

    /// İzin yoksa sistem penceresi açılmaz: macOS 27'de uygulamayı listeye eklemiyor, kullanıcı yolunu bulamıyordu
    /// (2026-10-17). İzin, ayarlarda kipin altındaki satırdan yönlendirmeyle verilir; gelince tap kendiliğinden kurulur.
    private func startTap() {
        if !Self.isAccessibilityTrusted {
            Log.integrations.notice("HUD: Erişilebilirlik izni bekleniyor")
            // İzin verilince sistem bu dağıtık bildirimi gönderir; tap o zaman kurulur.
            trustObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
                Task<Void, Never> { @MainActor [weak self] in
                    // Bildirim, izin veritabanı güncellenmeden hemen önce gelebiliyor.
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, self.mode == .replace, !self.isTapActive else { return }
                    self.isTapActive = Self.isAccessibilityTrusted && self.tap.start()
                    Log.integrations.notice("HUD: izin geldi, tap \(self.isTapActive ? "kuruldu" : "kurulamadı", privacy: .public)")
                }
            }
            return
        }
        isTapActive = tap.start()
        Log.integrations.notice("HUD: medya tuşu tap'i \(self.isTapActive ? "kuruldu" : "kurulamadı", privacy: .public)")
    }

    private func handle(_ key: MediaKey, fine: Bool) -> Bool {
        let step = fine ? Self.fineStep : Self.step
        switch key {
        case .soundUp, .soundDown:
            guard var volume = SystemVolume.volume().map(Double.init) else { return false }
            if key == .soundUp, SystemVolume.isMuted() { SystemVolume.setMuted(false) }
            volume = Self.stepped(volume, by: key == .soundUp ? step : -step, step: step)
            guard SystemVolume.setVolume(Float(volume)) else { return false }
            show(.volume, level: volume, muted: SystemVolume.isMuted())
            return true
        case .mute:
            let muted = !SystemVolume.isMuted()
            guard SystemVolume.setMuted(muted) else { return false }
            show(.volume, level: Double(SystemVolume.volume() ?? 0), muted: muted)
            return true
        case .brightnessUp, .brightnessDown:
            guard let display = Self.builtInDisplay(),
                  let current = DisplayBrightness.brightness(of: display) else { return false }
            let value = Self.stepped(Double(current), by: key == .brightnessUp ? step : -step, step: step)
            guard DisplayBrightness.setBrightness(Float(value), of: display) else { return false }
            show(.brightness, level: value, muted: false)
            return true
        case .illuminationUp, .illuminationDown:
            // Klavye ışığı private CoreBrightness ister; şimdilik sisteme bırakılır.
            Log.integrations.notice("HUD: klavye ışığı tuşu sisteme bırakıldı")
            return false
        }
    }

    /// Adım ızgarasına oturtur: 0,30'dayken artı adım bir sonraki ızgara noktası 0,3125'e gider
    /// (0,3625'e değil); ızgaradaki değerden ise tam bir adım.
    nonisolated static func stepped(_ value: Double, by delta: Double, step: Double) -> Double {
        let snapped = (value / step).rounded() * step
        let base = abs(snapped - value) < 0.001 ? snapped : (delta > 0 ? floor(value / step) * step : ceil(value / step) * step)
        return min(max(base + delta, 0), 1)
    }

    static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    // MARK: - overlay

    private func installVolumeListeners() {
        addListener(AudioObjectID(kAudioObjectSystemObject),
                    AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)) { [weak self] in
            self?.reinstallDeviceListeners()
        }
        reinstallDeviceListeners()
    }

    private func reinstallDeviceListeners() {
        for (object, address, block) in volumeListeners.dropFirst() {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        volumeListeners = Array(volumeListeners.prefix(1))
        guard let device = SystemVolume.defaultOutputDevice() else { return }
        for address in [SystemVolume.volumeAddress, SystemVolume.muteAddress] {
            addListener(device, address) { [weak self] in self?.scheduleVolumeRead() }
        }
    }

    private func addListener(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
                             _ handler: @escaping @MainActor () -> Void) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            volumeListeners.append((object, address, block))
        }
    }

    /// Aynı döngüdeki bildirimler (ana, sol, sağ kanal) tek okumada birleşir.
    private func scheduleVolumeRead() {
        guard !volumeReadPending else { return }
        volumeReadPending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.volumeReadPending = false
                self.show(.volume, level: Double(SystemVolume.volume() ?? 0), muted: SystemVolume.isMuted())
            }
        }
    }

    /// Sesi değiştirmeden mevcut düzeyi gösterir (önizleme ve testler için).
    public func previewCurrentVolume() {
        show(.volume, level: Double(SystemVolume.volume() ?? 0), muted: SystemVolume.isMuted())
    }

    // MARK: - Ortak

    private func show(_ kind: Kind, level: Double, muted: Bool) {
        Log.integrations.notice("HUD: \(kind == .volume ? "ses" : "parlaklık", privacy: .public) %\(Int((level * 100).rounded()), privacy: .public)\(muted ? " sessiz" : "", privacy: .public)")
        self.kind = kind
        self.level = level
        isMuted = muted
        onShow?()
    }

    private func tearDown() {
        tap.stop()
        isTapActive = false
        if let trustObserver { DistributedNotificationCenter.default().removeObserver(trustObserver) }
        trustObserver = nil
        for (object, address, block) in volumeListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        volumeListeners.removeAll()
    }
}
