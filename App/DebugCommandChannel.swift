#if DEBUG
import AppKit

/// Yalnız debug derlemesi: test betikleri notch'u imleci ele geçirmeden yönetebilsin.
/// Komutlar dağıtık bildirim nesnesi olarak gelir: open, close, tab:media|calendar|shelf, flash:power.
@MainActor
final class DebugCommandChannel {
    static let name = Notification.Name("com.talatozcoban.notchmvp.debug")
    private let coordinator: AppCoordinator
    private var token: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        token = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil,
                                                                    queue: .main) { [weak self] note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { self?.handle(command) }
        }
    }

    private func handle(_ command: String) {
        let models = coordinator.panels.models
        switch command {
        case "open":
            models.forEach { $0.tapped() }
        case "close":
            models.forEach { $0.dismiss() }
        case let tab where tab.hasPrefix("tab:"):
            if let value = NotchTab(rawValue: String(tab.dropFirst(4))) { coordinator.ui.selectedTab = value }
        case "flash:power":
            coordinator.activities.flash(AppCoordinator.ActivityKind.power, duration: .seconds(3))
        default:
            NSLog("Bilinmeyen debug komutu: \(command)")
        }
    }
}
#endif
