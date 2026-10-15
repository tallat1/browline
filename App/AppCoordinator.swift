import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable, Sendable {
    case media
    case calendar
    case shelf
    case activities
    case notes
    case timer
    case system
    case mirror
    case claude

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .shelf: "tray.full"
        case .activities: "square.stack.3d.up"
        case .notes: "note.text"
        case .timer: "timer"
        case .system: "cpu"
        case .mirror: "person.crop.square"
        case .claude: "sparkles"
        }
    }

    var title: String {
        switch self {
        case .media: String(localized: "Medya")
        case .calendar: String(localized: "Takvim")
        case .shelf: String(localized: "Raf")
        case .activities: String(localized: "Etkinlikler")
        case .notes: String(localized: "Not")
        case .timer: String(localized: "Zamanlayıcı")
        case .system: String(localized: "Sistem")
        case .mirror: String(localized: "Ayna")
        case .claude: "Claude"
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
    /// Pomodoro açıksa şu anki evre; düz zamanlayıcıda nil.
    var pomodoroPhase: Pomodoro.Phase?
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
        static let trackChange: ActivityID = "trackChange"
        static let audioOutput: ActivityID = "audioOutput"
        static let keepAwake: ActivityID = "keepAwake"
        static let timer: ActivityID = "timer"
        static let timerDone: ActivityID = "timerDone"
        static let batteryLow: ActivityID = "batteryLow"
        static let batteryFull: ActivityID = "batteryFull"
        static let claudeUsage: ActivityID = "claudeUsage"

        /// Başlık ya da çubuk taşıyan etkinlikler geniş kanat ister.
        static func wantsWideWing(_ id: ActivityID) -> Bool {
            id.rawValue.hasPrefix(externalPrefix)
                || [hud, download, downloadDone, trackChange, audioOutput, timerDone, batteryLow, batteryFull,
                    claudeUsage].contains(id)
        }

        /// Kilit ekranında yalnız kişisel içerik taşımayanlar: toplantı başlığı, dosya adı ve dış
        /// etkinlik metni bilgisayarın başındaki herkese görünür.
        static func isAllowedOnLockScreen(_ id: ActivityID) -> Bool {
            [nowPlaying, power, privacy, hud, timer, timerDone, keepAwake, batteryLow, batteryFull].contains(id)
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
    let audioOutput = AudioOutputMonitor()
    let keepAwake = KeepAwake()
    let timer = CountdownTimer()
    let mirror = CameraMirror()
    let reminders = RemindersMonitor()
    let systemStats = SystemStats()
    let weather = WeatherMonitor()
    let notes = NotesStore()
    let claudeUsage = ClaudeUsageMonitor()
    let ui = NotchUIState()
    private(set) var panels: PanelManager!
    private(set) var lockScreen: LockScreenPresenter!
    private var activityServer: ActivitySocketServer?
    private var liveExternalIDs: Set<ActivityID> = []
    /// Parça değişimini anlamak için bir önceki Now Playing bilgisi.
    private var lastTrackInfo: NowPlayingInfo?

    /// Etkin koordinatör; Kestirmeler eylemleri buradan ulaşır.
    private(set) static var current: AppCoordinator?

    init() {
        panels = PanelManager(options: settings.panelOptions) { [unowned self] model in
            AnyView(NotchRootView(model: model, coordinator: self))
        }
        lockScreen = LockScreenPresenter { [unowned self] model in
            AnyView(LockScreenRootView(model: model, coordinator: self))
        }
        Self.current = self
    }

    /// Kilit panelinde öne çıkan etkinlik.
    var lockScreenActivityID: ActivityID? {
        activities.current(allowing: ActivityKind.isAllowedOnLockScreen)?.id
    }

    /// Ana notch'ta öne çıkan etkinlik. macOS 27'de normal panel kilit ekranında da görünüyor
    /// (2026-10-15, kullanıcı denemesi); kilitliyken o da kilit kuralına uyar.
    var displayedActivityID: ActivityID? {
        lockScreen.isLocked ? lockScreenActivityID : activities.current?.id
    }

    func start() {
        activities.onActivitiesChanged = { [weak self] in self?.updateCompactState() }
        activities.onCurrentChanged = { activity in
            AppLog.coordinator.notice("öne çıkan etkinlik: \(activity?.id.rawValue ?? "yok", privacy: .public)")
        }
        panels.onModelsChanged = { [weak self] models in
            guard let self else { return }
            for model in models {
                model.onHorizontalSwipe = { [weak self] forward in self?.horizontalSwipe(forward: forward) }
            }
            updateCompactState()
        }

        nowPlaying.onInfoChanged = { [weak self] info in
            guard let self else { return }
            if settings.trackPeekEnabled, NowPlayingInfo.isTrackChange(from: lastTrackInfo, to: info) {
                activities.flash(ActivityKind.trackChange, duration: .seconds(3))
            }
            lastTrackInfo = info
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
        battery.onAlert = { [weak self] alert in
            guard let self else { return }
            switch alert {
            case .low: activities.flash(ActivityKind.batteryLow, duration: .seconds(4))
            case .full: activities.flash(ActivityKind.batteryFull, duration: .seconds(4))
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
            AppLog.coordinator.notice("gizlilik: kamera \(camera ? "açık" : "kapalı", privacy: .public), mikrofon \(microphone ? "açık" : "kapalı", privacy: .public)")
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
            AppLog.coordinator.notice("indirmeler: \(list.count) etkin")
            if list.isEmpty {
                activities.removeLive(ActivityKind.download)
            } else {
                activities.setLive(ActivityKind.download, priority: 25)
            }
        }
        downloads.onFinished = { [weak self] name in
            guard let self else { return }
            AppLog.coordinator.notice("indirme bitti")
            ui.lastFinishedDownload = name
            activities.flash(ActivityKind.downloadDone, duration: .seconds(3))
        }
        audioOutput.onChange = { [weak self] _ in
            self?.activities.flash(ActivityKind.audioOutput, duration: .seconds(3))
        }
        keepAwake.onChange = { [weak self] active in
            guard let self else { return }
            if active { activities.setLive(ActivityKind.keepAwake, priority: 5) } else { activities.removeLive(ActivityKind.keepAwake) }
        }
        timer.onRunningChanged = { [weak self] running in
            guard let self else { return }
            if running { activities.setLive(ActivityKind.timer, priority: 35) } else { activities.removeLive(ActivityKind.timer) }
        }
        timer.onFinished = { [weak self] in
            guard let self else { return }
            // Pomodoro'da sıradaki evre kendiliğinden başlar; bildirim yeni evreyi söyler.
            if let phase = ui.pomodoroPhase {
                let next = Pomodoro.next(after: phase)
                ui.pomodoroPhase = next
                timer.start(seconds: Pomodoro.duration(of: next))
            }
            activities.flash(ActivityKind.timerDone, duration: .seconds(5))
            NSSound(named: "Glass")?.play()
        }
        claudeUsage.onAlert = { [weak self] _ in
            self?.activities.flash(ActivityKind.claudeUsage, duration: .seconds(5))
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
        audioOutput.stop()
        reminders.stop()
        systemStats.stop()
        weather.stop()
        claudeUsage.stop()
        notes.flush()
        keepAwake.stop()
        cancelTimer()
        mirror.stop()
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
        toggle(settings.audioOutputAlertEnabled, start: audioOutput.start, stop: audioOutput.stop)
        toggle(settings.calendarEnabled && settings.remindersEnabled, start: reminders.start, stop: reminders.stop)
        if !settings.systemStatsEnabled { systemStats.stop() }
        toggle(settings.claudeUsageEnabled, start: claudeUsage.start, stop: claudeUsage.stop)
        if settings.weatherEnabled, let place = settings.weatherPlace { weather.start(place: place) } else { weather.stop() }
        if !settings.keepAwakeEnabled { keepAwake.stop() }
        if !settings.timerEnabled { cancelTimer() }
        if !settings.trackPeekEnabled { activities.cancelFlash(ActivityKind.trackChange) }
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

    /// Kullanıcının sırasıyla; modülü kapalı ya da gizlenmiş sekme yok.
    var availableTabs: [NotchTab] {
        settings.orderedTabs.filter { isModuleEnabled(for: $0) && !settings.hiddenTabs.contains($0) }
    }

    func isModuleEnabled(for tab: NotchTab) -> Bool {
        switch tab {
        case .media: settings.nowPlayingEnabled
        case .calendar: settings.calendarEnabled
        case .shelf: settings.shelfEnabled
        case .activities: settings.activityAPIEnabled
        case .notes: settings.notesEnabled
        case .timer: settings.timerEnabled
        case .system: settings.systemStatsEnabled
        case .mirror: settings.mirrorEnabled
        case .claude: settings.claudeUsageEnabled
        }
    }

    private func updateCompactState() {
        let displayed = displayedActivityID
        for model in panels.models {
            model.setCompact(for: displayed)
        }
        lockScreen.model?.setCompact(for: lockScreenActivityID)
    }

    func startPomodoro() {
        ui.pomodoroPhase = Pomodoro.first
        timer.start(seconds: Pomodoro.duration(of: Pomodoro.first))
    }

    /// Zamanlayıcıyı ve varsa Pomodoro döngüsünü durdurur.
    func cancelTimer() {
        ui.pomodoroPhase = nil
        timer.cancel()
    }

    /// Açık notch'ta yatay kaydırma: medya sekmesindeyken parça geçişi (Alcove).
    private func horizontalSwipe(forward: Bool) {
        guard ui.selectedTab == .media, nowPlaying.info != nil else { return }
        if forward { nowPlaying.nextTrack() } else { nowPlaying.previousTrack() }
        AppLog.coordinator.notice("kaydırma: \(forward ? "sonraki" : "önceki", privacy: .public) parça")
    }

    // MARK: - Etkinlik API'si

    /// URL şeması ve Kestirmeler soketi dolaşmadan buradan girer: aynı doğrulama, aynı ayar.
    func handleExternal(_ request: ActivityRequest, source: String) -> ActivityResponse {
        guard settings.activityAPIEnabled else {
            AppLog.coordinator.notice("\(source, privacy: .public) \(request.op.rawValue, privacy: .public): API kapalı")
            return .failure(String(localized: "Etkinlik API'si kapalı; Ayarlar › Modüller'den açın."))
        }
        let response = externalActivities.handle(request)
        // Başlık kişisel olabilir; günlüğe yalnız işlem ve sonuç.
        AppLog.coordinator.notice("\(source, privacy: .public) \(request.op.rawValue, privacy: .public): \(response.ok ? "tamam" : response.error ?? "hata", privacy: .public)")
        return response
    }

    func handleURL(_ url: URL) {
        do throws(ActivityURL.ParseError) {
            _ = handleExternal(try ActivityURL.request(from: url), source: "URL")
        } catch {
            AppLog.coordinator.error("URL reddedildi: \(error.description, privacy: .public)")
        }
    }

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
    func setCompact(for id: ActivityID?) {
        let hasContent = id != nil
        let wingWidth = id.map(AppCoordinator.ActivityKind.wantsWideWing) == true ? AppCoordinator.wideWingWidth : nil
        if hasCompactContent != hasContent { hasCompactContent = hasContent }
        if compactWingWidth != wingWidth { compactWingWidth = wingWidth }
    }
}
