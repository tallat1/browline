import Foundation
import IOKit.pwr_mgt
import Observation

/// Ekranı uyanık tutar (caffeinate benzeri). Public IOKit güç iddiası; `pmset -g assertions`
/// listesinde görünür. Süreç kapanınca sistem iddiayı kendiliğinden bırakır.
@MainActor
@Observable
public final class KeepAwake {
    public private(set) var isActive = false
    /// Süreli açıldıysa bitiş; süresizse nil.
    public private(set) var endsAt: Date?
    @ObservationIgnored public var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    public init() {}

    /// `duration` nil ise kapatılana kadar.
    @discardableResult
    public func start(for duration: Duration? = nil, reason: String) -> Bool {
        if !isActive {
            // kIOPMAssertionTypePreventUserIdleDisplaySleep bir CFSTR makrosu; Swift'e gelmiyor.
            var id: IOPMAssertionID = 0
            guard IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              reason as CFString, &id) == kIOReturnSuccess else { return false }
            assertion = id
            isActive = true
        }
        expiryTask?.cancel()
        endsAt = duration.map { Date.now.addingTimeInterval(TimeInterval($0.components.seconds)) }
        if let duration {
            expiryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        }
        Log.integrations.notice("Uyanık tutma açık (\(duration.map { "\($0.components.seconds) sn" } ?? "süresiz", privacy: .public))")
        onChange?(true)
        return true
    }

    public func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        endsAt = nil
        guard isActive else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isActive = false
        Log.integrations.notice("Uyanık tutma kapandı")
        onChange?(false)
    }
}
