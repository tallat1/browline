import AppKit
import CoreAudio
import Foundation
import Observation

/// Toplantı denetimi: varsayılan mikrofonu sistem genelinde sessize alır ve mikrofonu kullanan
/// uygulamayı bulur ("toplantıya dön"). İzin istemez: CoreAudio aygıt özelliği
/// (`kAudioDevicePropertyMute`, giriş kapsamı) ve süreç nesneleri (`kAudioProcessPropertyIsRunningInput`,
/// macOS 14+). Kamera kapatma ve toplantıdan ayrılma uygulamaya özgü (Erişilebilirlik izni gerekir),
/// burada yok.
///
/// Sessize alma aygıta yazılır, her uygulama sessiz duyar. Varsayılan giriş değişirse (AirPods takıldı)
/// sessizlik yeni aygıta taşınır; uygulama kapanırken bizim kapattığımız mikrofon geri açılır.
@MainActor
@Observable
public final class MicrophoneControl {
    public struct InputApp: Equatable, Sendable {
        public let name: String
        public let bundleIdentifier: String?
        public let processIdentifier: pid_t
    }

    public private(set) var isMuted = false
    /// Varsayılan girişte sessize alma yazılabiliyor mu (ya da ses düzeyi, geri düşüş).
    public private(set) var canMute = false
    /// Mikrofonu şu an kullanan uygulamalar (bu uygulama hariç).
    public private(set) var inputApps: [InputApp] = []
    @ObservationIgnored public var onChange: (() -> Void)?

    @ObservationIgnored private var device = AudioObjectID(kAudioObjectUnknown)
    /// Bizim sessize aldığımız aygıt: değişince taşınır, kapanırken açılır.
    @ObservationIgnored private var mutedByUs: AudioObjectID?
    /// Sessize alma özelliği olmayan aygıtta ses düzeyi 0'a çekilir; önceki düzey burada.
    @ObservationIgnored private var savedVolume: [AudioObjectID: Float32] = [:]
    @ObservationIgnored private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var isRunning = false

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        addListener(system, Self.address(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in
            self?.defaultInputChanged()
        }
        addListener(system, Self.address(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
            self?.refreshInputApps()
        }
        device = Self.defaultInputDevice()
        installDeviceListeners()
        refreshMute()
        refreshInputApps()
    }

    public func stop() {
        guard isRunning else { return }
        if let mutedByUs { apply(false, to: mutedByUs) }
        mutedByUs = nil
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
        isRunning = false
        isMuted = false
        canMute = false
        inputApps = []
    }

    public func toggleMute() { setMuted(!isMuted) }

    public func setMuted(_ muted: Bool) {
        guard device != kAudioObjectUnknown, apply(muted, to: device) else { return }
        mutedByUs = muted ? device : nil
        refreshMute()
    }

    /// Mikrofonu kullanan uygulamayı öne getirir; tarayıcıdaki toplantıda tarayıcı gelir.
    public func activateInputApp() {
        guard let app = inputApps.first,
              let running = NSRunningApplication(processIdentifier: app.processIdentifier) else { return }
        running.activate()
    }

    /// Süreç izleyicisi her girişi yakalamayabiliyor (ör. aygıt çalışıyor, süreç değişmedi); gizlilik
    /// göstergesi değişince de çağrılır.
    public func refreshInputApps() {
        guard isRunning else { return }
        let own = ProcessInfo.processInfo.processIdentifier
        var seen = Set<pid_t>()
        var apps: [InputApp] = []
        for process in Self.processObjects() where Self.uint(process, kAudioProcessPropertyIsRunningInput) == 1 {
            guard let pid = Self.pid(process), pid != own,
                  let app = Self.owningApplication(pid: pid), seen.insert(app.processIdentifier).inserted else { continue }
            apps.append(InputApp(name: app.localizedName ?? app.bundleIdentifier ?? "?",
                                 bundleIdentifier: app.bundleIdentifier, processIdentifier: app.processIdentifier))
        }
        if apps != inputApps {
            inputApps = apps
            onChange?()
        }
    }

    // MARK: - Aygıt

    private func defaultInputChanged() {
        let old = device
        device = Self.defaultInputDevice()
        // Sessizlik yeni aygıta taşınır: toplantı ortasında kulaklık değişince ses açılmasın.
        if let mutedByUs, mutedByUs == old, old != device {
            apply(false, to: old)
            self.mutedByUs = apply(true, to: device) ? device : nil
        }
        installDeviceListeners()
        refreshMute()
    }

    private func installDeviceListeners() {
        // İlk ikisi sistem dinleyicileri; aygıtınkiler yenilenir.
        for (object, address, block) in listeners.dropFirst(2) {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners = Array(listeners.prefix(2))
        guard device != kAudioObjectUnknown else { return }
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            let address = Self.address(selector, scope: kAudioObjectPropertyScopeInput)
            var probe = address
            guard AudioObjectHasProperty(device, &probe) else { continue }
            addListener(device, address) { [weak self] in self?.refreshMute() }
        }
    }

    private func refreshMute() {
        let muted: Bool
        if device == kAudioObjectUnknown {
            muted = false
            canMute = false
        } else if Self.isSettable(device, kAudioDevicePropertyMute) {
            muted = Self.uint(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput) == 1
            canMute = true
        } else if Self.isSettable(device, kAudioDevicePropertyVolumeScalar) {
            muted = savedVolume[device] != nil && (Self.volume(device) ?? 1) == 0
            canMute = true
        } else {
            muted = false
            canMute = false
        }
        if muted != isMuted {
            isMuted = muted
            // Başka yerden (Denetim Merkezi, toplantı uygulaması değil, aygıt) açıldıysa artık bizim değil.
            if !muted { mutedByUs = nil }
            onChange?()
        }
    }

    @discardableResult
    private func apply(_ muted: Bool, to device: AudioObjectID) -> Bool {
        if Self.isSettable(device, kAudioDevicePropertyMute) {
            var address = Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
            var value: UInt32 = muted ? 1 : 0
            return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        }
        guard Self.isSettable(device, kAudioDevicePropertyVolumeScalar) else { return false }
        var target: Float32
        if muted {
            if savedVolume[device] == nil { savedVolume[device] = Self.volume(device) ?? 1 }
            target = 0
        } else {
            guard let saved = savedVolume.removeValue(forKey: device) else { return true }
            target = saved
        }
        var address = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &target) == noErr
    }

    private func addListener(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
                             _ handler: @escaping @MainActor () -> Void) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    // MARK: - CoreAudio okuma

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultInputDevice() -> AudioObjectID {
        uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice)
            .map { AudioObjectID($0) } ?? AudioObjectID(kAudioObjectUnknown)
    }

    static func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = address(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func volume(_ device: AudioObjectID) -> Float32? {
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func isSettable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector, scope: kAudioObjectPropertyScopeInput)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static func processObjects() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    static func pid(_ process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    /// Mikrofonu çoğu zaman yardımcı süreç tutar (Chrome Helper, WebKit): sahibi olan uygulama,
    /// yolu içeren en dıştaki `.app` paketiyle bulunur.
    static func owningApplication(pid: pid_t) -> NSRunningApplication? {
        guard let process = NSRunningApplication(processIdentifier: pid) else { return nil }
        if process.activationPolicy == .regular { return process }
        guard let path = (process.bundleURL ?? process.executableURL)?.path,
              let range = path.range(of: ".app/") ?? path.range(of: ".app", options: .backwards) else { return process }
        let outer = URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.bundleURL?.standardizedFileURL == outer.standardizedFileURL
        } ?? process
    }
}
