import Foundation
import IOKit
import Observation

/// Bağlı Bluetooth aygıtları ve pilleri. İzin istemez: bağlantı olayları IOKit kayıt defterindeki
/// `IOBluetoothDevice` nesnelerinden (IOBluetooth API'si Bluetooth izni penceresi açtırırdı), aygıt
/// adı ve piller macOS'un `system_profiler` aracından (tek çağrı ≈ 0,1 sn, 0,02 sn işlemci). Pil bağlıyken
/// 5 dakikada bir tazelenir; aygıt yoksa iş yok.
@MainActor
@Observable
public final class BluetoothMonitor {
    public struct Device: Identifiable, Equatable, Sendable {
        public enum Kind: String, Sendable {
            case headphones, keyboard, mouse, trackpad, speaker, gamepad, other
        }

        public var id: String { name }
        public let name: String
        public let kind: Kind
        public var main: Int?
        public var left: Int?
        public var right: Int?
        public var caseLevel: Int?

        public init(name: String, kind: Kind, main: Int? = nil, left: Int? = nil, right: Int? = nil,
                    caseLevel: Int? = nil) {
            self.name = name
            self.kind = kind
            self.main = main
            self.left = left
            self.right = right
            self.caseLevel = caseLevel
        }

        /// Dar yerler için aygıt adı: "Talat (AirPods Pro)" → "AirPods Pro", "Talat’s Keyboard" → "Keyboard".
        public var shortName: String {
            if name.hasSuffix(")"), let open = name.lastIndex(of: "("), open > name.startIndex {
                let inner = name[name.index(after: open)..<name.index(before: name.endIndex)]
                if !inner.trimmingCharacters(in: .whitespaces).isEmpty { return String(inner) }
            }
            for marker in ["’s ", "'s "] {
                if let range = name.range(of: marker), range.upperBound < name.endIndex {
                    return String(name[range.upperBound...])
                }
            }
            return name
        }

        /// Uyarı için en düşük pil; kutu hariç (kulaklıklar takılıyken kutu boşalabilir).
        public var lowest: Int? { [main, left, right].compactMap { $0 }.min() }
    }

    public private(set) var devices: [Device] = []
    @ObservationIgnored public var onConnected: ((Device) -> Void)?
    @ObservationIgnored public var onDisconnected: ((Device) -> Void)?
    @ObservationIgnored public var onLowBattery: ((Device, Int) -> Void)?

    @ObservationIgnored private var port: IONotificationPortRef?
    @ObservationIgnored private var iterators: [io_iterator_t] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoaded = false
    /// Aygıt başına en son uyarılan eşik: aynı eşik için bir kez.
    @ObservationIgnored private var warnedThreshold: [String: Int] = [:]

    static let lowThresholds = [20, 10]
    static let batteryRefreshInterval: Duration = .seconds(300)
    /// Bağlantıdan hemen sonra pil henüz bildirilmemiş olabiliyor.
    static let settleDelay: Duration = .milliseconds(1500)

    public init() {}

    public var isRunning: Bool { port != nil }

    public func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        self.port = port
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let callback: IOServiceMatchingCallback = { refcon, iterator in
                drainIterator(iterator)
                guard let refcon else { return }
                let monitor = Unmanaged<BluetoothMonitor>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.scheduleRefresh(after: BluetoothMonitor.settleDelay) }
            }
            if IOServiceAddMatchingNotification(port, type, IOServiceMatching("IOBluetoothDevice"), callback,
                                                refcon, &iterator) == KERN_SUCCESS {
                // Var olanlar tüketilmeden bildirim kurulmaz.
                drainIterator(iterator)
                iterators.append(iterator)
            }
        }
        scheduleRefresh(after: .zero)
        periodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.batteryRefreshInterval)
                guard let self, !Task.isCancelled else { return }
                if !self.devices.isEmpty { self.scheduleRefresh(after: .zero) }
            }
        }
    }

    public func stop() {
        iterators.forEach { IOObjectRelease($0) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
        refreshTask?.cancel()
        periodicTask?.cancel()
        refreshTask = nil
        periodicTask = nil
        devices = []
        hasLoaded = false
        warnedThreshold.removeAll()
    }

    private func scheduleRefresh(after delay: Duration) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let data = await Task.detached(priority: .utility) { Self.runProfiler() }.value
            guard let self, !Task.isCancelled, let data else { return }
            self.apply(Self.parse(data))
        }
    }

    /// Bağlanan/ayrılan aygıtlar ve pil eşikleri. İlk okumada var olanlar "bağlandı" sayılmaz.
    func apply(_ new: [Device]) {
        let oldNames = Set(devices.map(\.name))
        let newNames = Set(new.map(\.name))
        if hasLoaded {
            for device in new where !oldNames.contains(device.name) { onConnected?(device) }
            for device in devices where !newNames.contains(device.name) {
                onDisconnected?(device)
                warnedThreshold[device.name] = nil
            }
        }
        for device in new {
            guard let lowest = device.lowest else { continue }
            if lowest > Self.lowThresholds.max() ?? 20 {
                warnedThreshold[device.name] = nil
                continue
            }
            guard let threshold = Self.lowThresholds.filter({ lowest <= $0 }).min() else { continue }
            if warnedThreshold[device.name].map({ threshold < $0 }) ?? true {
                warnedThreshold[device.name] = threshold
                onLowBattery?(device, lowest)
            }
        }
        if new != devices { devices = new }
        hasLoaded = true
    }

    nonisolated static func runProfiler() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "-detailLevel", "mini", "SPBluetoothDataType"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// `SPBluetoothDataType[0].device_connected`: [{ad: {device_minorType, device_batteryLevel…}}].
    /// Aynı ad iki kez gelebiliyor (AirPods kutusu ayrı kayıt); alanlar birleştirilir. Pil "%15",
    /// "15%" ya da "15 %" biçiminde (bölgeye göre) gelir.
    nonisolated static func parse(_ data: Data) -> [Device] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = (object["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = root["device_connected"] as? [[String: Any]] else { return [] }
        var order: [String] = []
        var merged: [String: Device] = [:]
        for entry in connected {
            for (name, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                let kind = Self.kind(info["device_minorType"] as? String)
                var device = merged[name] ?? Device(name: name, kind: kind)
                if device.kind == .other { device = Device(name: name, kind: kind, main: device.main, left: device.left,
                                                           right: device.right, caseLevel: device.caseLevel) }
                device.main = device.main ?? level(info["device_batteryLevelMain"])
                device.left = device.left ?? level(info["device_batteryLevelLeft"])
                device.right = device.right ?? level(info["device_batteryLevelRight"])
                device.caseLevel = device.caseLevel ?? level(info["device_batteryLevelCase"])
                if merged[name] == nil { order.append(name) }
                merged[name] = device
            }
        }
        return order.compactMap { merged[$0] }
    }

    nonisolated static func kind(_ minorType: String?) -> Device.Kind {
        switch minorType?.lowercased() ?? "" {
        case let type where type.contains("headphone") || type.contains("headset"): .headphones
        case let type where type.contains("keyboard"): .keyboard
        case let type where type.contains("mouse"): .mouse
        case let type where type.contains("trackpad"): .trackpad
        case let type where type.contains("speaker"): .speaker
        case let type where type.contains("gamepad") || type.contains("joystick"): .gamepad
        default: .other
        }
    }

    nonisolated static func level(_ value: Any?) -> Int? {
        guard let text = value as? String else { return (value as? NSNumber)?.intValue }
        let digits = text.filter(\.isNumber)
        return Int(digits).flatMap { (0...100).contains($0) ? $0 : nil }
    }
}

/// IOKit yineleyicisi tüketilmeden yeni bildirim gelmez.
private func drainIterator(_ iterator: io_iterator_t) {
    while case let object = IOIteratorNext(iterator), object != 0 {
        IOObjectRelease(object)
    }
}
