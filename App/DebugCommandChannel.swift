#if DEBUG
import AppKit
import os

private let debugLog = Logger(subsystem: "com.talatozcoban.notchmvp", category: "debug")

/// Yalnız debug derlemesi: test betikleri notch'u imleci ele geçirmeden yönetebilsin.
/// Komutlar dağıtık bildirim nesnesi olarak gelir: open, close, tab:media|calendar|shelf|activities,
/// flash:power, hud:preview, state, lock:on|lock:off (kilit benzetimi, SkyLight kullanmaz).
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
        case "hud:preview":
            coordinator.hud.previewCurrentVolume()
            let hud = coordinator.hud
            debugLog.info("HUD önizleme: düzey \(hud.level, privacy: .public), sessiz \(hud.isMuted, privacy: .public)")
        case "lock:on", "lock:off":
            let accepted = coordinator.lockScreen.simulateLock(command == "lock:on")
            debugLog.info("kilit benzetimi \(command, privacy: .public): \(accepted ? "uygulandı" : "reddedildi (özellik açık)", privacy: .public)")
        case "state":
            let summary = "gizlilik [\(coordinator.privacy.deviceSummary)], HUD \(coordinator.hud.mode.rawValue), "
                + "indirmeler \(coordinator.downloads.isRunning ? "açık" : "kapalı"), "
                + "kilit ekranı \(coordinator.lockScreen.status) (kilitli: \(coordinator.lockScreen.isLocked))"
            debugLog.info("durum: \(summary, privacy: .public)")
        default:
            debugLog.error("bilinmeyen debug komutu: \(command, privacy: .public)")
        }
    }
}
#endif
