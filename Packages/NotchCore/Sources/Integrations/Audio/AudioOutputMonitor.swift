import CoreAudio
import Observation

/// Varsayılan ses çıkışı değişince (AirPods bağlandı, hoparlöre dönüldü) haber verir. Public CoreAudio,
/// izin istemez; olay güdümlü, yoklama yok. AirPods pil düzeyi public değil, okunmaz.
@MainActor
@Observable
public final class AudioOutputMonitor {
    public enum Transport: Sendable {
        case builtIn, bluetooth, usb, display, airPlay, other
    }

    public struct Device: Equatable, Sendable {
        public let id: AudioObjectID
        public let name: String
        public let transport: Transport

        public init(id: AudioObjectID, name: String, transport: Transport) {
            self.id = id
            self.name = name
            self.transport = transport
        }
    }

    public private(set) var current: Device?
    /// Yalnız geçişte; açılıştaki ilk okuma bildirilmez.
    @ObservationIgnored public var onChange: ((Device) -> Void)?
    @ObservationIgnored private var listener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    public init() {}

    public var isRunning: Bool { listener != nil }

    public func start() {
        guard listener == nil else { return }
        current = Self.readDefault()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        var address = Self.defaultOutputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            listener = block
        }
    }

    public func stop() {
        guard let listener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
        current = nil
    }

    private func refresh() {
        guard let device = Self.readDefault(), device != current else { return }
        current = device
        Log.integrations.notice("Ses çıkışı değişti: \(String(describing: device.transport), privacy: .public)")
        onChange?(device)
    }

    private static func readDefault() -> Device? {
        guard let id = SystemVolume.defaultOutputDevice() else { return nil }
        return Device(id: id, name: name(of: id) ?? "", transport: transport(of: id))
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func transport(of device: AudioObjectID) -> Transport {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return .other }
        return transport(rawValue: value)
    }

    nonisolated static func transport(rawValue: UInt32) -> Transport {
        switch rawValue {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: .display
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        default: .other
        }
    }

    /// Çıkışın ses düzeyi (0–100); ayarlanamayan cihazda nil.
    public nonisolated static func volumePercent() -> Int? {
        SystemVolume.volume().map { Int(($0 * 100).rounded()) }
    }

    /// SF Symbol: cihaz adından AirPods türü, yoksa bağlantı türünden.
    public nonisolated static func symbolName(for device: Device) -> String {
        let name = device.name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        switch device.transport {
        case .builtIn: return "laptopcomputer"
        case .bluetooth: return "headphones"
        case .usb: return "hifispeaker.fill"
        case .display: return "tv"
        case .airPlay: return "airplayaudio"
        case .other: return "speaker.wave.2.fill"
        }
    }
}
