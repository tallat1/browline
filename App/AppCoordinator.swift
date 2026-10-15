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
        case .media: String(localized: "Medya")
        case .calendar: String(localized: "Takvim")
        case .shelf: String(localized: "Raf")
        case .activities: String(localized: "Etkinlikler")
        }
    }
}

/// Açık notch'taki seçili sekme; tüm ekranlarda ortak.
@MainActor
@Observable
final class NotchUIState {
    var selectedTab: NotchTab = .media
    var activityAPIStatus = String(localized: "Kapalı")
    /// Son tamamlanan indirmenin adı (kısa bildirimde gösterilir).
    var lastFinishedDownload = ""
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
        static let privacy: ActivityID = "privacy"
        static let hud: ActivityID = "hud"
        static let download: ActivityID = "download"
        static let downloadDone: ActivityID = "downloadDone"

        /// Başlık ya da çubuk taşıyan etkinlikler geniş kanat ister.
        static func wantsWideWing(_ id: ActivityID) -> Bool {
            id.rawValue.hasPrefix(externalPrefix) || [hud, download, downloadDone].contains(id)
        }

        /// Kilit ekranında yalnız kişisel içerik taşımayanlar: toplantı başlığı, dosya adı ve dış
        /// etkinlik metni bilgisayarın başındaki herkese görünür.
        static func isAllowedOnLockScreen(_ id: ActivityID) -> Bool {
            [nowPlaying, power, privacy, hud].contains(id)
        }
    }

    /// Başlık taşıyan dış etkinlikler için kompakt kanat genişliği.
    static let wideWingWidth: CGFloat = 136

    let settings = AppSettings()
    let activities = ActivityCenter()
    let nowPlaying = NowPlayingController()
    let battery = BatteryMonitor()
    let calendar = CalendarMonitor()
    let shelf = ShelfStore()
    let externalActivities = ExternalActivityStore()
    let privacy = PrivacyIndicatorMonitor()
    let hud = HUDController()
    let downloads = DownloadsMonitor()
    let ui = NotchUIState()
    private(set) var panels: PanelManager!
    private(set) var lockScreen: LockScreenPresenter!
    private var activityServer: ActivitySocketServer?
    private var liveExternalIDs: Set<ActivityID> = []

    init() {
        panels = PanelManager(options: settings.panelOptions) { [unowned self] model in
            AnyView(NotchRootView(model: model, coordinator: self))
        }
        lockScreen = LockScreenPresenter { [unowned self] model in
            AnyView(LockScreenRootView(model: model, coordinator: self))
        }
    }

    /// Kilit panelinde öne çıkan etkinlik.
    var lockScreenActivityID: ActivityID? {
        activities.current(allowing: ActivityKind.isAllowedOnLockScreen)?.id
    }

    func start() {
        activities.onActivitiesChanged = { [weak self] in self?.updateCompactState() }
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
        privacy.onChange = { [weak self] camera, microphone in
            guard let self else { return }
            if camera || microphone {
                activities.setLive(ActivityKind.privacy, priority: 15)
            } else {
                activities.removeLive(ActivityKind.privacy)
            }
        }
        hud.onShow = { [weak self] in
            self?.activities.flash(ActivityKind.hud, priority: 2_000, duration: .milliseconds(1500))
        }
        downloads.onActiveChanged = { [weak self] list in
            guard let self else { return }
            if list.isEmpty {
                activities.removeLive(ActivityKind.download)
            } else {
                activities.setLive(ActivityKind.download, priority: 25)
            }
        }
        downloads.onFinished = { [weak self] name in
            guard let self else { return }
            ui.lastFinishedDownload = name
            activities.flash(ActivityKind.downloadDone, duration: .seconds(3))
        }
        settings.onChange = { [weak self] in self?.applySettings() }
        lockScreen.onLockChanged = { [weak self] locked in
            guard let self else { return }
            // Ana panel kilit altında kalır; açık kalmasın ki kilit açılınca raf ya da takvim görünmesin.
            if locked { panels.models.forEach { $0.dismiss() } }
            settings.setLockSessionOpen(locked && lockScreen.status == .ready)
            updateCompactState()
        }

        panels.start()
        lockScreen.start()
        applySettings()
    }

    func stop() {
        setActivityAPI(enabled: false)
        hud.setMode(.off)
        privacy.stop()
        downloads.stop()
        nowPlaying.stop()
        battery.stop()
        calendar.stop()
        lockScreen.stop()
        settings.setLockSessionOpen(false)
        panels.stop()
    }

    /// Ayarlar her değiştiğinde idempotent olarak uygulanır.
    func applySettings() {
        panels.options = settings.panelOptions
        toggle(settings.nowPlayingEnabled, start: nowPlaying.start, stop: nowPlaying.stop)
        toggle(settings.batteryEnabled, start: battery.start, stop: battery.stop)
        toggle(settings.calendarEnabled, start: calendar.start, stop: calendar.stop)
        setActivityAPI(enabled: settings.activityAPIEnabled)
        toggle(settings.privacyIndicatorEnabled, start: privacy.start, stop: privacy.stop)
        toggle(settings.downloadsEnabled, start: downloads.start, stop: downloads.stop)
        hud.setMode(settings.hudMode)
        lockScreen.setLayoutConfig(settings.panelOptions.layout)
        lockScreen.setEnabled(settings.lockScreenEnabled)
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
        let wing: CGFloat? = current.map { ActivityKind.wantsWideWing($0.id) } == true ? Self.wideWingWidth : nil
        for model in panels.models {
            model.setCompact(hasContent: hasCompact, wingWidth: wing)
        }
        if let model = lockScreen.model {
            let id = lockScreenActivityID
            model.setCompact(hasContent: id != nil, wingWidth: id.map(ActivityKind.wantsWideWing) == true ? Self.wideWingWidth : nil)
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
                ui.activityAPIStatus = String(localized: "Dinliyor: \(server.socketURL.path)")
            } catch {
                ui.activityAPIStatus = String(localized: "Başlatılamadı: \(String(describing: error))")
            }
        } else if !enabled, let server = activityServer {
            server.stop()
            activityServer = nil
            ui.activityAPIStatus = String(localized: "Kapalı")
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
        case .checking: String(localized: "Now Playing: denetleniyor…")
        case .mediaRemote: String(localized: "Now Playing: MediaRemote (sistem geneli)")
        case let .playerNotifications(reason): String(localized: "Now Playing: Music/Spotify yedeği (\(reason.localizedText))")
        case .off: String(localized: "Now Playing: kapalı")
        }
    }
}

extension NowPlayingController.FallbackReason {
    var localizedText: String {
        switch self {
        case .adapterMissing: String(localized: "adaptör uygulama paketinde yok")
        case .adapterTestFailed: String(localized: "adaptör testi bu macOS sürümünde başarısız")
        case .adapterLaunchFailed: String(localized: "adaptör başlatılamadı")
        case let .adapterExited(status): String(localized: "adaptör \(Int(status)) koduyla kapandı")
        }
    }
}

private extension NotchSurfaceModel {
    /// Yalnız değişince atar; gözlemciler boşuna tetiklenmesin.
    func setCompact(hasContent: Bool, wingWidth: CGFloat?) {
        if hasCompactContent != hasContent { hasCompactContent = hasContent }
        if compactWingWidth != wingWidth { compactWingWidth = wingWidth }
    }
}
