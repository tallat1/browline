import Foundation
import IOKit.ps
import Observation

/// Pil durumu, IOKit güç kaynağı bildirimiyle (olay güdümlü, izin istemez, yoklama yok).
@MainActor
@Observable
public final class BatteryMonitor {
    public struct State: Equatable, Sendable {
        public var percent: Int
        public var isCharging: Bool
        public var isPluggedIn: Bool
        /// Dakika; sistem hesaplıyorsa.
        public var minutesToFull: Int?
        public var minutesToEmpty: Int?
    }

    public private(set) var state: State?
    /// Fiş takılıp çıkarıldığında; uygulama geçici bir etkinlik gösterir.
    @ObservationIgnored public var onPowerSourceChanged: ((_ old: State?, _ new: State) -> Void)?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    public init() {}

    public func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // Kaynak ana run loop'a eklendi; geri çağrı ana iş parçacığında gelir.
            MainActor.assumeIsolated {
                Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
            }
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        refresh()
    }

    public func stop() {
        guard let source = runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = nil
    }

    private func refresh() {
        let new = Self.read()
        guard new != state else { return }
        let old = state
        state = new
        if let new, old?.isPluggedIn != new.isPluggedIn { onPowerSourceChanged?(old, new) }
    }

    /// Dahili pil yoksa (masaüstü Mac) nil.
    static func read() -> State? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let toFull = description[kIOPSTimeToFullChargeKey] as? Int
            let toEmpty = description[kIOPSTimeToEmptyKey] as? Int
            return State(
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                // -1 = sistem henüz hesaplıyor.
                minutesToFull: toFull.flatMap { $0 > 0 ? $0 : nil },
                minutesToEmpty: toEmpty.flatMap { $0 > 0 ? $0 : nil })
        }
        return nil
    }
}
