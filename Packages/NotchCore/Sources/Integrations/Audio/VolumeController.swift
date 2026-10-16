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
    /// CoreAudio sorguları coreaudiod'a gider (her biri milisaniyeler): ana iş parçacığında yapılınca
    /// kaydırıcı sürüklenirken ana iş parçacığı %35'e kadar meşgul oluyordu (2026-10-16 örneklemesi).
    @ObservationIgnored private let audioQueue = DispatchQueue(label: "com.talatozcoban.browline.volume", qos: .userInitiated)
    @ObservationIgnored private var readPending = false
    @ObservationIgnored private var pendingVolume: Float?
    @ObservationIgnored private var unmuteBeforeWrite = false
    @ObservationIgnored private var writeInFlight = false
    @ObservationIgnored private var lastLocalWrite = Date.distantPast
    /// Kendi yazdığımız değerin dinleyiciden dönen yankısı bu süre içinde kaydırıcıyı geri çekmez.
    static let echoWindow: TimeInterval = 0.4

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

    /// Arayüz hemen güncellenir; yazma ayrı kuyrukta ve birleşik: sürüklerken yalnız son değer yazılır.
    public func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        lastLocalWrite = .now
        if clamped > 0, isMuted {
            isMuted = false
            unmuteBeforeWrite = true
        }
        pendingVolume = Float(clamped)
        if !writeInFlight { flushWrite() }
    }

    private func flushWrite() {
        guard let target = pendingVolume else {
            writeInFlight = false
            return
        }
        pendingVolume = nil
        writeInFlight = true
        let unmute = unmuteBeforeWrite
        unmuteBeforeWrite = false
        audioQueue.async { [weak self] in
            if unmute { _ = SystemVolume.setMuted(false) }
            let succeeded = SystemVolume.setVolume(target)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !succeeded { Log.integrations.error("Ses ayarlanamadı") }
                    if self.pendingVolume != nil {
                        self.flushWrite()
                    } else {
                        self.writeInFlight = false
                        Log.integrations.notice("Ses ayarlandı: %\(Int((target * 100).rounded()))")
                    }
                }
            }
        }
    }

    public func toggleMute() {
        if SystemVolume.setMuted(!isMuted) { isMuted.toggle() }
        Log.integrations.notice("Sessiz: \(self.isMuted ? "açık" : "kapalı", privacy: .public)")
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
        else { Log.integrations.notice("Çıkış seçildi: \(String(describing: device.transport), privacy: .public)") }
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
                addListener(device, address) { [weak self] in self?.scheduleRead() }
            }
        }
        // Ayarlanabilirlik cihaza bağlı: yalnız cihaz değişince sorulur, her ses değişiminde değil.
        isSettable = Self.isVolumeSettable()
        scheduleRead()
    }

    /// Dinleyici bir değişimde kanal başına birkaç kez çağrılır; okumalar tek işte birleşir ve ayrı
    /// kuyrukta yapılır.
    private func scheduleRead() {
        guard !readPending else { return }
        readPending = true
        audioQueue.async { [weak self] in
            let level = SystemVolume.volume()
            let muted = SystemVolume.isMuted()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.readPending = false
                    // Kendi sürüklememizin yankısı kaydırıcıyı geri çekmesin.
                    if Date.now.timeIntervalSince(self.lastLocalWrite) > Self.echoWindow, !self.writeInFlight {
                        self.volume = Double(level ?? 0)
                    }
                    self.isMuted = muted
                }
            }
        }
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
