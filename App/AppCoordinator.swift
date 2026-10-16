import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Açık notch'un sekmeleri. "Şimdi" hep ilk ve sabit; şeritte en çok 4 sabitlenmiş sekme, kalanlar
/// Diğer menüsünde (karmaşıklık bütçesi, 2026-10-16 tasarım turu).
enum NotchTab: String, CaseIterable, Identifiable, Sendable {
    case now
    case calendar
    case shelf
    case activities
    case notes
    case timer
    case system
    case mirror
    case claude
    case terminal
    case clipboard

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .now: "house"
        case .calendar: "calendar"
        case .shelf: "tray.full"
        case .activities: "square.stack.3d.up"
        case .notes: "note.text"
        case .timer: "timer"
        case .system: "cpu"
        case .mirror: "person.crop.square"
        case .claude: "sparkles"
        case .terminal: "terminal"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var title: String {
        switch self {
        case .now: String(localized: "Şimdi")
        case .calendar: String(localized: "Takvim")
        case .shelf: String(localized: "Raf")
        case .activities: String(localized: "Etkinlikler")
        case .notes: String(localized: "Not")
        case .timer: String(localized: "Zamanlayıcı")
        case .system: String(localized: "Sistem")
        case .mirror: String(localized: "Ayna")
        case .claude: "Claude"
        case .terminal: String(localized: "Terminal")
        case .clipboard: String(localized: "Pano")
        }
    }
}

/// Açık notch'taki seçili sekme; tüm ekranlarda ortak.
@MainActor
@Observable
final class NotchUIState {
    var selectedTab: NotchTab = .now
    /// ••• şeridi (diğer sekmeler) açık mı.
    var isMoreTabsOpen = false
    var activityAPIStatus = String(localized: "Kapalı")
    /// Son tamamlanan indirmenin adı (kısa bildirimde gösterilir).
    var lastFinishedDownload = ""
    /// Pomodoro açıksa şu anki evre; düz zamanlayıcıda nil.
    var pomodoroPhase: Pomodoro.Phase?
    /// Son Bluetooth olayı (kısa bildirimde gösterilir).
    var bluetoothEvent: BluetoothEvent?
}

/// Bluetooth kısa bildirimi: hangi aygıt, ne oldu.
struct BluetoothEvent: Equatable {
    enum Change: Equatable {
        case connected, disconnected
        case lowBattery(Int)
    }

    let device: BluetoothMonitor.Device
    let change: Change
    let date: Date
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
        /// Onay sorusu toplantıdan (40) ve Now Playing'den (30) önde.
        static let questionPriority = 48
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
        static let bluetooth: ActivityID = "bluetooth"

        /// Başlık ya da çubuk taşıyan etkinlikler geniş kanat ister.
        static func wantsWideWing(_ id: ActivityID) -> Bool {
            id.rawValue.hasPrefix(externalPrefix)
                || [hud, download, downloadDone, trackChange, audioOutput, timerDone, batteryLow, batteryFull,
                    claudeUsage, bluetooth].contains(id)
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
    let volume = VolumeController()
    let keepAwake = KeepAwake()
    let timer = CountdownTimer()
    let mirror = CameraMirror()
    let reminders = RemindersMonitor()
    let systemStats = SystemStats()
    let weather = WeatherMonitor()
    let notes = NotesStore()
    let claudeUsage = ClaudeUsageMonitor()
    let terminal = TerminalSession()
    let clipboard = ClipboardHistory()
    let bluetooth = BluetoothMonitor()
    let microphone = MicrophoneControl()
    let spectrum = AudioSpectrum()
    /// Dış onay soruları (Claude Code izin istemleri): notch'ta İzin ver / Reddet.
    let questions = QuestionStore()
    /// Soru gelince açılan notch'lar; son soru yanıtlanınca yalnız bunlar kapanır.
    private var questionOpenedModels: [ObjectIdentifier] = []
    private var shownQuestionIDs: Set<String> = []
    /// Ayar penceresini uygulama temsilcisi açar (notch'taki Diğer menüsünden "Sekmeleri düzenle").
    var openSettings: (() -> Void)?
    let ui = NotchUIState()
    private(set) var panels: PanelManager!
    private(set) var lockScreen: LockScreenPresenter!
    private var activityServer: ActivitySocketServer?
    private var liveExternalIDs: Set<ActivityID> = []
    /// Parça değişimini anlamak için bir önceki Now Playing bilgisi.
    private var lastTrackInfo: NowPlayingInfo?
    /// Şarkı geçişinde oynatıcı bir an duraklıyor; kanat hemen kapanmasın.
    private var nowPlayingRemovalTask: Task<Void, Never>?

    /// Şarkı önizlemesinin süresi: kısa adda 3 sn; uzun ad kayarak sonuna kadar okunabilsin diye
    /// kayan yazının bir turu kadar.
    static func trackPeekDuration(for title: String) -> Duration {
        // Geniş kanatta başlığa kalan genişlik: kanat − baş boşluk (10) − kapak (20) − aralık (6).
        readableFlashDuration(base: .seconds(3), text: title, available: wideWingWidth - 36)
    }

    /// Kısa bildirimin süresi: en az `base`; metin geniş kanada sığmıyorsa kayan yazının bir turu
    /// kadar. Ürün genelinde tek kural: bildirim, metni okunmadan kaybolmaz.
    /// Kamera/mikrofon kullanımı ve mikrofon sessizliği. Sessizdeyken müzikten ve toplantıdan önde:
    /// konuştuğunu sanıp sessizde kalınmasın.
    func updatePrivacyActivity() {
        let muted = isMicrophoneMuted
        if privacy.isCameraActive || privacy.isMicrophoneActive || muted {
            activities.setLive(ActivityKind.privacy, priority: muted ? 45 : 15)
        } else {
            activities.removeLive(ActivityKind.privacy)
        }
    }

    var isMicrophoneMuted: Bool { settings.meetingControlsEnabled && microphone.isMuted }

    /// Bağlanma, ayrılma ve düşük pil; düşük pil biraz daha uzun kalır.
    func flashBluetooth(_ device: BluetoothMonitor.Device, _ change: BluetoothEvent.Change) {
        let kind = switch change {
        case .connected: "bağlandı"
        case .disconnected: "ayrıldı"
        case let .lowBattery(level): "pil %\(level)"
        }
        AppLog.coordinator.notice("bluetooth \(device.kind.rawValue, privacy: .public): \(kind, privacy: .public)")
        ui.bluetoothEvent = BluetoothEvent(device: device, change: change, date: .now)
        let base: Duration = if case .lowBattery = change { .seconds(4) } else { .seconds(3) }
        activities.flash(ActivityKind.bluetooth, duration: Self.readableFlashDuration(base: base, text: device.shortName))
    }

    static func readableFlashDuration(base: Duration, text: String,
                                      available: CGFloat = WideWingLabel.textWidth) -> Duration {
        let overflow = MarqueeText.width(of: text, size: 13, weight: .semibold) - available
        let needed = Duration.milliseconds(Int((NotchMotion.marqueeCycle(overflow: overflow) + 0.4) * 1000))
        return max(base, needed)
    }

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
            if settings.trackPeekEnabled, let info, NowPlayingInfo.isTrackChange(from: lastTrackInfo, to: info) {
                activities.flash(ActivityKind.trackChange, duration: Self.trackPeekDuration(for: info.title))
            }
            lastTrackInfo = info
            // Kompakt kanatlar yalnız çalarken; duraklatılmış parça açık notch'ta görünmeye devam eder.
            // Duraklama hemen değil kısa bir payla kanadı kapatır: şarkı geçişindeki anlık duraklama
            // notch'u kapatıp yeniden açmasın.
            if info?.isPlaying == true {
                nowPlayingRemovalTask?.cancel()
                nowPlayingRemovalTask = nil
                activities.setLive(ActivityKind.nowPlaying, priority: 30)
            } else if activities.isLive(ActivityKind.nowPlaying), nowPlayingRemovalTask == nil {
                nowPlayingRemovalTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard let self, !Task.isCancelled else { return }
                    self.nowPlayingRemovalTask = nil
                    if self.nowPlaying.info?.isPlaying != true { self.activities.removeLive(ActivityKind.nowPlaying) }
                }
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
        questions.onQuestionsChanged = { [weak self] list in self?.questionsChanged(list) }
        questions.onResolved = { question, decision, reason in
            let waited = Int(Date.now.timeIntervalSince(question.askedAt).rounded())
            AppLog.coordinator.notice("onay sorusu kapandı: \(reason.rawValue, privacy: .public), karar \(decision?.rawValue ?? "yok", privacy: .public), \(waited) sn (\(question.subtitle ?? "", privacy: .public))")
        }
        externalActivities.onFlash = { [weak self] activity, duration in
            // İstenen süre en az; uzun başlık sonuna kadar kayabilsin diye gerekirse uzar.
            self?.activities.flash(ActivityKind.externalFlash,
                                   duration: Self.readableFlashDuration(base: duration, text: activity.title))
        }
        privacy.onChange = { [weak self] camera, microphone in
            guard let self else { return }
            AppLog.coordinator.notice("gizlilik: kamera \(camera ? "açık" : "kapalı", privacy: .public), mikrofon \(microphone ? "açık" : "kapalı", privacy: .public)")
            self.microphone.refreshInputApps()
            updatePrivacyActivity()
        }
        microphone.onChange = { [weak self] in
            guard let self else { return }
            let muted = microphone.isMuted
            let apps = microphone.inputApps.count
            AppLog.coordinator.notice("mikrofon: \(muted ? "sessiz" : "açık", privacy: .public), kullanan \(apps) uygulama")
            updatePrivacyActivity()
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
        audioOutput.onChange = { [weak self] device in
            guard let self else { return }
            // Az önce bağlandığı gösterilen kulaklık ikinci kez (ses çıkışı olarak) duyurulmaz.
            if let event = ui.bluetoothEvent, event.change == .connected, event.device.name == device.name,
               Date.now.timeIntervalSince(event.date) < 6 { return }
            activities.flash(ActivityKind.audioOutput,
                             duration: Self.readableFlashDuration(base: .seconds(3), text: device.name))
        }
        bluetooth.onConnected = { [weak self] in self?.flashBluetooth($0, .connected) }
        bluetooth.onDisconnected = { [weak self] in self?.flashBluetooth($0, .disconnected) }
        bluetooth.onLowBattery = { [weak self] device, level in self?.flashBluetooth(device, .lowBattery(level)) }
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
        volume.stop()
        reminders.stop()
        systemStats.stop()
        weather.stop()
        claudeUsage.stop()
        terminal.stop()
        clipboard.stop()
        bluetooth.stop()
        // Bizim kapattığımız mikrofon çıkarken geri açılır.
        microphone.stop()
        spectrum.isEnabled = false
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
        // Terminal sekme açılınca başlar; modül kapatılınca kabuk sonlanır.
        if !settings.terminalEnabled { terminal.stop() }
        toggle(settings.clipboardEnabled, start: clipboard.start, stop: clipboard.stop)
        toggle(settings.batteryEnabled, start: battery.start, stop: battery.stop)
        toggle(settings.calendarEnabled, start: calendar.start, stop: calendar.stop)
        setActivityAPI(enabled: settings.activityAPIEnabled)
        toggle(settings.privacyIndicatorEnabled, start: privacy.start, stop: privacy.stop)
        toggle(settings.downloadsEnabled, start: downloads.start, stop: downloads.stop)
        toggle(settings.audioOutputAlertEnabled, start: audioOutput.start, stop: audioOutput.stop)
        toggle(settings.bluetoothEnabled, start: bluetooth.start, stop: bluetooth.stop)
        toggle(settings.meetingControlsEnabled, start: microphone.start, stop: microphone.stop)
        spectrum.isEnabled = settings.animatedEqualizer && settings.reactiveEqualizer
        updatePrivacyActivity()
        toggle(settings.calendarEnabled && settings.remindersEnabled, start: reminders.start, stop: reminders.stop)
        if !settings.systemStatsEnabled { systemStats.stop() }
        toggle(settings.claudeUsageEnabled, start: claudeUsage.start, stop: claudeUsage.stop)
        claudeUsage.setAPIEnabled(settings.claudeUsageEnabled && settings.claudeUsageAPIEnabled)
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
        questions.isEnabled = settings.questionsEnabled && settings.activityAPIEnabled
        // Kapatılınca bekleyen sorular "yanıt yok"la çözülür: istemci kendi akışına döner.
        if !questions.isEnabled { questions.questions.forEach { questions.answer($0.id, with: nil) } }
    }

    private func toggle(_ enabled: Bool, start: () -> Void, stop: () -> Void) {
        if enabled { start() } else { stop() }
    }

    /// Şeritteki sekmeler: Şimdi + kullanıcının sabitledikleri (modülü açık olanlar).
    var stripTabs: [NotchTab] {
        [.now] + settings.pinnedTabs.filter { $0 != .now && isModuleEnabled(for: $0) }
    }

    /// Diğer menüsündekiler: sabitlenmemiş, gizlenmemiş, modülü açık sekmeler.
    var overflowTabs: [NotchTab] {
        NotchTab.allCases.filter {
            $0 != .now && !settings.pinnedTabs.contains($0) && !settings.hiddenTabs.contains($0) && isModuleEnabled(for: $0)
        }
    }

    var availableTabs: [NotchTab] { stripTabs + overflowTabs }

    func isModuleEnabled(for tab: NotchTab) -> Bool {
        switch tab {
        // Şimdi her zaman var: müzik kapalıysa da toplantı, etkinlik ve zamanlayıcı orada.
        case .now: true
        case .calendar: settings.calendarEnabled
        case .shelf: settings.shelfEnabled
        case .activities: settings.activityAPIEnabled
        case .notes: settings.notesEnabled
        case .timer: settings.timerEnabled
        case .system: settings.systemStatsEnabled
        case .mirror: settings.mirrorEnabled
        case .claude: settings.claudeUsageEnabled
        case .terminal: settings.terminalEnabled
        case .clipboard: settings.clipboardEnabled
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
        guard ui.selectedTab == .now, nowPlaying.info != nil else { return }
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
            let questions = questions
            let server = ActivitySocketServer { request in
                request.op == .ask ? await questions.ask(request) : await store.handle(request)
            }
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

    /// Yeni soru gelince notch açılır ve sabitlenir (pencere etkinleşmez, yazı yazılan uygulama bölünmez);
    /// kapalı notch'ta "izin istiyor" canlı etkinliği görünür. Son soru yanıtlanınca yalnız soru yüzünden
    /// açılan notch'lar kapanır.
    private func questionsChanged(_ list: [ExternalQuestion]) {
        let ids = Set(list.map(\.id))
        let arrived = !ids.subtracting(shownQuestionIDs).isEmpty
        shownQuestionIDs = ids
        if let first = list.first {
            _ = externalActivities.handle(ActivityRequest(
                op: .push, id: Self.questionActivityID, title: first.title, subtitle: first.subtitle,
                symbol: first.symbol ?? "hand.raised.fill", tint: first.tint ?? "#FF9F0A",
                priority: ActivityKind.questionPriority, ttl: max(1, first.expiresAt.timeIntervalSinceNow)))
            if arrived {
                AppLog.coordinator.notice("onay sorusu geldi (\(list.count) bekliyor): \(first.subtitle ?? first.title, privacy: .public)")
                for model in panels.models where !model.isOpen {
                    model.tapped()
                    questionOpenedModels.append(ObjectIdentifier(model))
                }
            }
        } else {
            _ = externalActivities.handle(ActivityRequest(op: .end, id: Self.questionActivityID))
            let opened = Set(questionOpenedModels)
            for model in panels.models where opened.contains(ObjectIdentifier(model)) { model.dismiss() }
            questionOpenedModels.removeAll()
        }
    }

    static let questionActivityID = "notch.question"

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
