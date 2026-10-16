import Foundation
import Observation

/// macOS Düşük Güç Modu (Sistem Ayarları › Pil). Açıkken uygulama sürekli animasyonları durdurur.
/// `NSProcessInfoPowerStateDidChange` ile olay güdümlü; izin istemez, yoklama yok.
@MainActor
@Observable
public final class LowPowerMode {
    public private(set) var isEnabled = false
    @ObservationIgnored public var onChange: ((Bool) -> Void)?
    /// Debug: sistemi değiştirmeden denemek için (nil = gerçek durum).
    @ObservationIgnored public var override: Bool? { didSet { refresh() } }
    @ObservationIgnored private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func refresh() {
        let enabled = override ?? ProcessInfo.processInfo.isLowPowerModeEnabled
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        onChange?(enabled)
    }
}
