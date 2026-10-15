import CoreAudio
import Observation

/// Medya sekmesindeki ses kaydırıcısı ve çıkış seçici. Public CoreAudio, izin istemez. Dinleyiciler
/// yalnız sekme ekrandayken kurulur; kapalıyken iş yok.
@MainActor
@Observable
public final class VolumeController {
    public struct OutputDevice: Identifiable, Equatable, Sendable {
        public let id: AudioObjectID
        public let name: String
        public let transport: AudioOutputMonitor.Transport
    }

    /// 0…1
    public private(set) var volume: Double = 0
    public private(set) var isMuted = false
    /// Bazı HDMI/USB çıkışlarında ses ayarlanamaz.
    public private(set) var isSettable = false
    public private(set) var devices: [OutputDevice] = []
    public private(set) var currentDeviceID: AudioObjectID?

    @ObservationIgnored private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init() {}

    public var isRunning: Bool { !listeners.isEmpty }

    public func start() {
        guard listeners.isEmpty else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            addListener(system, AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                          mElement: kAudioObjectPropertyElementMain)) { [weak self] in
                self?.deviceChanged()
            }
        }
        deviceChanged()
    }

    public func stop() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
    }

    public func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        if clamped > 0, isMuted { SystemVolume.setMuted(false) }
        if SystemVolume.setVolume(Float(clamped)) { volume = clamped }
    }

    public func toggleMute() {
        if SystemVolume.setMuted(!isMuted) { isMuted.toggle() }
    }

    /// Varsayılan çıkışı değiştirir (Denetim Merkezi › Ses ile aynı iş).
    public func selectOutput(_ device: OutputDevice) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = device.id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &id)
        if status != noErr { Log.integrations.error("Çıkış değiştirilemedi: \(status)") }
    }

    // MARK: - Okuma

    /// Varsayılan cihaz değişince cihaza bağlı dinleyiciler yeniden kurulur.
    private func deviceChanged() {
        for (object, address, block) in listeners.dropFirst(2) {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners = Array(listeners.prefix(2))
        devices = Self.outputDevices()
        currentDeviceID = SystemVolume.defaultOutputDevice()
        if let device = currentDeviceID {
            for address in [SystemVolume.volumeAddress, SystemVolume.muteAddress] {
                addListener(device, address) { [weak self] in self?.readLevel() }
            }
        }
        readLevel()
    }

    private func readLevel() {
        volume = Double(SystemVolume.volume() ?? 0)
        isMuted = SystemVolume.isMuted()
        isSettable = Self.isVolumeSettable()
    }

    private func addListener(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
                             _ handler: @escaping @MainActor () -> Void) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private static func isVolumeSettable() -> Bool {
        guard let device = SystemVolume.defaultOutputDevice() else { return false }
        var address = SystemVolume.volumeAddress
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    /// Çıkış akışı olan cihazlar; sanal toplama cihazları dahil, ad sırasıyla.
    private static func outputDevices() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id -> OutputDevice? in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
                  let name = AudioOutputMonitor.name(of: id) else { return nil }
            return OutputDevice(id: id, name: name, transport: AudioOutputMonitor.transport(of: id))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
