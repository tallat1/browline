import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case media
    case calendar
    case shelf

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .shelf: "tray.full"
        }
    }

    var title: String {
        switch self {
        case .media: "Medya"
        case .calendar: "Takvim"
        case .shelf: "Raf"
        }
    }
}

/// Açık notch'taki seçili sekme; tüm ekranlarda ortak.
@MainActor
@Observable
final class NotchUIState {
    var selectedTab: NotchTab = .media
}

/// Modülleri birbirine bağlar: entegrasyonlar etkinlik üretir, etkinlik motoru kompakt içeriği
/// seçer, panel yöneticisi her ekranda notch'u çizer. Modül kapatılınca arka plan işi de durur.
@MainActor
final class AppCoordinator {
    enum ActivityKind {
        static let nowPlaying: ActivityID = "nowPlaying"
        static let meeting: ActivityID = "meeting"
        static let power: ActivityID = "power"
    }

    let settings = AppSettings()
    let activities = ActivityCenter()
    let nowPlaying = NowPlayingController()
    let battery = BatteryMonitor()
    let calendar = CalendarMonitor()
    let shelf = ShelfStore()
    let ui = NotchUIState()
    private(set) var panels: PanelManager!

    init() {
        panels = PanelManager(options: settings.panelOptions) { [unowned self] model in
            AnyView(NotchRootView(model: model, coordinator: self))
        }
    }

    func start() {
        activities.onCurrentChanged = { [weak self] _ in self?.updateCompactState() }
        panels.onModelsChanged = { [weak self] _ in self?.updateCompactState() }

        nowPlaying.onInfoChanged = { [weak self] info in
            guard let self else { return }
            // Kompakt kanatlar yalnız çalarken; duraklatılmış parça açık notch'ta görünmeye devam eder.
            if info?.isPlaying == true {
                activities.setLive(ActivityKind.nowPlaying, priority: 30)
            } else {
                activities.removeLive(ActivityKind.nowPlaying)
            }
        }
        calendar.onImminentMeetingChanged = { [weak self] event in
            guard let self else { return }
            if event != nil {
                activities.setLive(ActivityKind.meeting, priority: 40)
            } else {
                activities.removeLive(ActivityKind.meeting)
            }
        }
        battery.onPowerSourceChanged = { [weak self] old, _ in
            // İlk okuma değişiklik değildir; yalnız fiş takılıp çıkarıldığında göster.
            guard let self, old != nil else { return }
            activities.flash(ActivityKind.power, duration: .seconds(3))
        }
        settings.onChange = { [weak self] in self?.applySettings() }

        panels.start()
        applySettings()
    }

    func stop() {
        nowPlaying.stop()
        battery.stop()
        calendar.stop()
        panels.stop()
    }

    /// Ayarlar her değiştiğinde idempotent olarak uygulanır.
    func applySettings() {
        panels.options = settings.panelOptions
        toggle(settings.nowPlayingEnabled, start: nowPlaying.start, stop: nowPlaying.stop)
        toggle(settings.batteryEnabled, start: battery.start, stop: battery.stop)
        toggle(settings.calendarEnabled, start: calendar.start, stop: calendar.stop)
        if !settings.nowPlayingEnabled { activities.removeLive(ActivityKind.nowPlaying) }
        if !settings.calendarEnabled { activities.removeLive(ActivityKind.meeting) }
        if !settings.batteryEnabled { activities.cancelFlash(ActivityKind.power) }
        if !availableTabs.contains(ui.selectedTab), let first = availableTabs.first { ui.selectedTab = first }
    }

    private func toggle(_ enabled: Bool, start: () -> Void, stop: () -> Void) {
        if enabled { start() } else { stop() }
    }

    var availableTabs: [NotchTab] {
        var tabs: [NotchTab] = []
        if settings.nowPlayingEnabled { tabs.append(.media) }
        if settings.calendarEnabled { tabs.append(.calendar) }
        if settings.shelfEnabled { tabs.append(.shelf) }
        return tabs
    }

    private func updateCompactState() {
        let hasCompact = activities.current != nil
        for model in panels.models where model.hasCompactContent != hasCompact {
            model.hasCompactContent = hasCompact
        }
    }

    var nowPlayingSourceDescription: String {
        switch nowPlaying.source {
        case .checking: "Now Playing: denetleniyor…"
        case .mediaRemote: "Now Playing: MediaRemote (sistem geneli)"
        case let .playerNotifications(reason): "Now Playing: Music/Spotify yedeği (\(reason))"
        case .off: "Now Playing: kapalı"
        }
    }
}
