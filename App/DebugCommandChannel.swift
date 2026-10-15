#if DEBUG
import AppKit
import Integrations
import NotchShell
import os

private let debugLog = Logger(subsystem: "com.talatozcoban.notchmvp", category: "debug")

/// Yalnız debug derlemesi: test betikleri notch'u imleci ele geçirmeden yönetebilsin.
/// Komutlar dağıtık bildirim nesnesi olarak gelir: open, close, tab:media|calendar|shelf|activities,
/// flash:power, hud:preview, state, lock:on|lock:off (kilit benzetimi, SkyLight kullanmaz),
/// display:floating|off|reset (birinci ekranın modu), timer:<sn>|cancel, audio:preview, track:preview,
/// awake:on|off, battery:low|full, weather:<şehir>|off, timer:pomodoro.
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
        case "display:floating", "display:off", "display:reset":
            // Birinci ekranın (yerleşik) modunu dener; reset seçimi siler, önceki duruma döner.
            guard let display = PanelManager.displaySummaries(for: coordinator.settings.panelOptions).first else { break }
            let mode = PanelManager.DisplayMode(rawValue: String(command.dropFirst("display:".count)))
            coordinator.settings.displayModes[display.persistentID] = mode
            debugLog.info("ekran modu \(command, privacy: .public): \(display.name, privacy: .public)")
        case let timer where timer.hasPrefix("timer:"):
            if timer == "timer:cancel" { coordinator.cancelTimer() }
            else if timer == "timer:pomodoro" { coordinator.startPomodoro() }
            else if let seconds = Double(timer.dropFirst(6)) { coordinator.timer.start(seconds: seconds) }
        case "audio:preview":
            coordinator.activities.flash(AppCoordinator.ActivityKind.audioOutput, duration: .seconds(3))
        case "track:preview":
            let title = coordinator.nowPlaying.info?.title ?? ""
            coordinator.activities.flash(AppCoordinator.ActivityKind.trackChange,
                                         duration: AppCoordinator.trackPeekDuration(for: title))
        case "awake:on":
            coordinator.keepAwake.start(for: .seconds(90), reason: "NotchMVP debug")
        case "awake:off":
            coordinator.keepAwake.stop()
        case "battery:low":
            coordinator.activities.flash(AppCoordinator.ActivityKind.batteryLow, duration: .seconds(4))
        case "battery:full":
            coordinator.activities.flash(AppCoordinator.ActivityKind.batteryFull, duration: .seconds(4))
        case let command where command.hasPrefix("weather:"):
            // Ayarları değiştirmeden dener; ayar kapalıysa sonraki ayar değişikliği durdurur.
            let city = String(command.dropFirst("weather:".count))
            if city == "off" { coordinator.weather.stop(); break }
            Task { @MainActor in
                if let place = try? await WeatherMonitor.geocode(city) { coordinator.weather.start(place: place) }
            }
        case "claude:limit-preview":
            // ÖRNEK veri: 2 sa 13 dk sonra sıfırlanacak 5 saatlik limit.
            coordinator.claudeUsage.previewLimit([ClaudeLimitHit(type: "five_hour",
                                                                 resetsAt: .now.addingTimeInterval(7_980), hitAt: .now)])
        case "sessions":
            let nowPlaying = coordinator.nowPlaying
            let list = nowPlaying.sessions.map { "\($0.id) \($0.info.isPlaying ? "▶" : "⏸") \($0.info.title)" }
            debugLog.info("oturumlar (odak \(nowPlaying.focusedSessionID ?? "-", privacy: .public)): \(list.joined(separator: " | "), privacy: .public)")
        case let command where command.hasPrefix("session:"):
            // Yalnız gösterilen oturumu değiştirir; çalmaya dokunmaz.
            if let index = Int(command.dropFirst("session:".count)), coordinator.nowPlaying.sessions.indices.contains(index) {
                coordinator.nowPlaying.selectSession(coordinator.nowPlaying.sessions[index].id)
            }
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
