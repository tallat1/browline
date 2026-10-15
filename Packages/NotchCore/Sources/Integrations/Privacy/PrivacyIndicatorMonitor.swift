import CoreAudio
import CoreMediaIO
import Foundation
import Observation

/// Kamera ve mikrofon başka bir uygulama tarafından kullanılıyor mu. Public CoreMediaIO ve CoreAudio
/// "running somewhere" özellikleri; olay güdümlü, izin istemez.
/// ⚠️ Bilinen sınırlar (Apple forumları): Bluetooth mikrofonlar etkin değilmiş gibi raporlanabiliyor;
/// CMIO geri çağrısı yanlış tetiklenebiliyor, bu yüzden değer her çağrıda yeniden okunur.
@MainActor
@Observable
public final class PrivacyIndicatorMonitor {
    public private(set) var isCameraActive = false
    public private(set) var isMicrophoneActive = false
    @ObservationIgnored public var onChange: ((_ camera: Bool, _ microphone: Bool) -> Void)?

    @ObservationIgnored private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var cameraListeners: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var isRunning = false

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        // Cihaz listesi değişince (kulaklık takıldı, kamera bağlandı) dinleyiciler yeniden kurulur.
        addAudioListener(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices) { [weak self] in
            self?.reinstallDeviceListeners()
        }
        addCameraListener(CMIOObjectID(kCMIOObjectSystemObject), selector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)) { [weak self] in
            self?.reinstallDeviceListeners()
        }
        reinstallDeviceListeners()
    }

    /// Tanılama: izlenen cihaz sayıları (giriş akışı olan ses cihazları, kameralar).
    public var deviceSummary: String {
        "ses girişi \(Self.audioDevices().filter(Self.hasInputStreams).count), kamera \(Self.cameraDevices().count), "
            + "mikrofon \(isMicrophoneActive ? "açık" : "kapalı"), kamera \(isCameraActive ? "açık" : "kapalı")"
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        removeAllListeners()
        update(camera: false, microphone: false)
    }

    private func reinstallDeviceListeners() {
        guard isRunning else { return }
        // Sistem nesnesi dinleyicileri (ilk ikisi) kalır, cihazınkiler yenilenir.
        for (object, address, block) in audioListeners.dropFirst() {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        audioListeners = Array(audioListeners.prefix(1))
        for (object, address, block) in cameraListeners.dropFirst() {
            var address = address
            CMIOObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        cameraListeners = Array(cameraListeners.prefix(1))

        for device in Self.audioDevices() where Self.hasInputStreams(device) {
            addAudioListener(device, selector: kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in
                self?.refresh()
            }
        }
        for device in Self.cameraDevices() {
            addCameraListener(device, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)) {
                [weak self] in self?.refresh()
            }
        }
        refresh()
    }

    private func removeAllListeners() {
        for (object, address, block) in audioListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        for (object, address, block) in cameraListeners {
            var address = address
            CMIOObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        audioListeners.removeAll()
        cameraListeners.removeAll()
    }

    private func refresh() {
        let microphone = Self.audioDevices().contains { Self.hasInputStreams($0) && Self.isRunningSomewhere(audio: $0) }
        let camera = Self.cameraDevices().contains { Self.isRunningSomewhere(camera: $0) }
        update(camera: camera, microphone: microphone)
    }

    private func update(camera: Bool, microphone: Bool) {
        guard camera != isCameraActive || microphone != isMicrophoneActive else { return }
        isCameraActive = camera
        isMicrophoneActive = microphone
        onChange?(camera, microphone)
    }

    // MARK: - Dinleyiciler

    private func addAudioListener(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                                  _ handler: @escaping @MainActor () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            audioListeners.append((object, address, block))
        }
    }

    private func addCameraListener(_ object: CMIOObjectID, selector: CMIOObjectPropertySelector,
                                   _ handler: @escaping @MainActor () -> Void) {
        var address = CMIOObjectPropertyAddress(mSelector: selector,
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let block: CMIOObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        if CMIOObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            cameraListeners.append((object, address, block))
        }
    }

    // MARK: - Okuma

    static func audioDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    static func isRunningSomewhere(audio device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    static func cameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return [] }
        return devices
    }

    static func isRunningSomewhere(camera device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var value: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
            == noErr && value != 0
    }
}
