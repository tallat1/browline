import ActivityAPI
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
    case activities

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .shelf: "tray.full"
        case .activities: "square.stack.3d.up"
        }
    }

    var title: String {
        switch self {
        case .media: "Medya"
        case .calendar: "Takvim"
        case .shelf: "Raf"
        case .activities: "Etkinlikler"
        }
    }
}

/// Açık notch'taki seçili sekme; tüm ekranlarda ortak.
@MainActor
@Observable
final class NotchUIState {
    var selectedTab: NotchTab = .media
    var activityAPIStatus = "Kapalı"
}

/// Modülleri birbirine bağlar: entegrasyonlar etkinlik üretir, etkinlik motoru kompakt içeriği
/// seçer, panel yöneticisi her ekranda notch'u çizer. Modül kapatılınca arka plan işi de durur.
@MainActor
final class AppCoordinator {
    enum ActivityKind {
        static let nowPlaying: ActivityID = "nowPlaying"
        static let meeting: ActivityID = "meeting"
        static let power: ActivityID = "power"
        /// Dış etkinlikler "ext." önekiyle; kısa bildirim tek kimlikte.
        static let externalPrefix = "ext."
        static let externalFlash: ActivityID = "ext.flash"
    }

    /// Başlık taşıyan dış etkinlikler için kompakt kanat genişliği.
    static let wideWingWidth: CGFloat = 128

    let settings = AppSettings()
    let activities = ActivityCenter()
    let nowPlaying = NowPlayingController()
    let battery = BatteryMonitor()
    let calendar = CalendarMonitor()
    let shelf = ShelfStore()
    let externalActivities = ExternalActivityStore()
    let ui = NotchUIState()
    private(set) var panels: PanelManager!
    private var activityServer: ActivitySocketServer?
    private var liveExternalIDs: Set<ActivityID> = []

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
        externalActivities.onActivitiesChanged = { [weak self] list in self?.syncExternal(list) }
        externalActivities.onFlash = { [weak self] _, duration in
            self?.activities.flash(ActivityKind.externalFlash, duration: duration)
        }
        settings.onChange = { [weak self] in self?.applySettings() }

        panels.start()
        applySettings()
    }

    func stop() {
        setActivityAPI(enabled: false)
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
        setActivityAPI(enabled: settings.activityAPIEnabled)
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
        if settings.activityAPIEnabled { tabs.append(.activities) }
        return tabs
    }

    private func updateCompactState() {
        let current = activities.current
        let hasCompact = current != nil
        let wing: CGFloat? = current.map { $0.id.rawValue.hasPrefix(ActivityKind.externalPrefix) } == true
            ? Self.wideWingWidth : nil
        for model in panels.models {
            if model.hasCompactContent != hasCompact { model.hasCompactContent = hasCompact }
            if model.compactWingWidth != wing { model.compactWingWidth = wing }
        }
    }

    // MARK: - Etkinlik API'si

    /// Kompakt görünüm için: öne çıkan kimliğe karşılık gelen dış etkinlik ya da kısa bildirim.
    func externalActivity(for id: ActivityID?) -> ExternalActivity? {
        guard let id else { return nil }
        if id == ActivityKind.externalFlash { return externalActivities.flash }
        return externalActivities.activities.first { ActivityKind.externalPrefix + $0.id == id.rawValue }
    }

    var cliPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/notch").path
    }

    private func setActivityAPI(enabled: Bool) {
        if enabled, activityServer == nil {
            let store = externalActivities
            let server = ActivitySocketServer { request in await store.handle(request) }
            do {
                try server.start()
                activityServer = server
                ui.activityAPIStatus = "Dinliyor: \(server.socketURL.path)"
            } catch {
                ui.activityAPIStatus = "Başlatılamadı: \(error)"
            }
        } else if !enabled, let server = activityServer {
            server.stop()
            activityServer = nil
            ui.activityAPIStatus = "Kapalı"
            syncExternal([])
            activities.cancelFlash(ActivityKind.externalFlash)
        }
    }

    private func syncExternal(_ list: [ExternalActivity]) {
        let wanted = Set(list.map { ActivityID(ActivityKind.externalPrefix + $0.id) })
        for id in liveExternalIDs where !wanted.contains(id) { activities.removeLive(id) }
        for activity in list {
            activities.setLive(ActivityID(ActivityKind.externalPrefix + activity.id), priority: activity.priority)
        }
        liveExternalIDs = wanted
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
