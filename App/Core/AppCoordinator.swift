import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Bileşim kökü: servisleri kurar ve yaşam döngüsünü yönetir. Entegrasyonlar etkinlik üretir, etkinlik
/// motoru kompakt içeriği seçer, panel yöneticisi her ekranda notch'u çizer; modül kapatılınca arka plan işi
/// de durur. Ayrıntılar amaç bazlı uzantılarda: `+Wiring` (servis → etkinlik), `+Settings`, `+Navigation`,
/// `+Visibility`, `+ExternalAPI`, `+Actions`, `+ActivityKind`.
@MainActor
final class AppCoordinator {
    // MARK: - Servisler

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
    let lowPower = LowPowerMode()
    let screenRecording = ScreenRecordingMonitor()
    let ci = CIMonitor()
    /// Sparkle 2; Debug derlemesinde başlatılmaz.
    let updater = AppUpdater()
    /// Dış onay soruları (Claude Code izin istemleri): notch'ta İzin ver / Reddet.
    let questions = QuestionStore()

    // MARK: - Arayüz durumu ve paneller

    let ui = NotchUIState()
    private(set) var panels: PanelManager!
    private(set) var lockScreen: LockScreenPresenter!
    /// İzin durumları (yalnız ayarlar açılınca kurulur).
    private(set) lazy var permissions = PermissionCenter(coordinator: self)
    /// Etkin koordinatör; Kestirmeler eylemleri buradan ulaşır.
    private(set) static var current: AppCoordinator?

    // MARK: - Uygulama temsilcisinin bağladığı geri çağrılar

    /// Ayar penceresini uygulama temsilcisi açar (notch'taki Diğer menüsünden "Sekmeleri düzenle").
    var openSettings: (() -> Void)?
    var closeSettings: (() -> Void)?
    var openOnboarding: (() -> Void)?
    /// Menü çubuğu simgesi durum değişince (mikrofon sessiz, notch gizli) yenilenir.
    var onStatusIconChange: (() -> Void)?
    #if DEBUG
    var onboardingStepForDebug: ((Int) -> Void)?
    var closeOnboarding: (() -> Void)?
    var showStatusMenuForCapture: (() -> Void)?
    #endif

    // MARK: - Uzantıların paylaştığı durum
    // AppCoordinator+… dosyaları kullandığı için private değil; dışarıdan yazılmamalı.

    /// Sistem geneli sessize alma kısayolu; `start()`'ta kurulur.
    var micShortcut: GlobalShortcut?
    var registeredMicShortcut: GlobalShortcut.Preset?
    /// Soru gelince açılan notch'lar; son soru yanıtlanınca yalnız bunlar kapanır.
    var questionOpenedModels: [ObjectIdentifier] = []
    var shownQuestionIDs: Set<String> = []
    var unhideTask: Task<Void, Never>?
    var activityServer: ActivitySocketServer?
    var liveExternalIDs: Set<ActivityID> = []
    /// Parça değişimini anlamak için bir önceki Now Playing bilgisi.
    var lastTrackInfo: NowPlayingInfo?
    /// Şarkı geçişinde oynatıcı bir an duraklıyor; kanat hemen kapanmasın.
    var nowPlayingRemovalTask: Task<Void, Never>?
    /// Karar kartı izin beklerken Erişilebilirlik izninin gelmesini izler.
    var accessibilityWatch: Task<Void, Never>?

    init() {
        panels = PanelManager(options: settings.panelOptions) { [unowned self] model in
            AnyView(NotchRootView(model: model, coordinator: self))
        }
        lockScreen = LockScreenPresenter { [unowned self] model in
            AnyView(LockScreenRootView(model: model, coordinator: self))
        }
        Self.current = self
    }

    func start() {
        wireCore()
        wireMedia()
        wireCalendar()
        wireIndicators()
        wireExternalAPI()
        wireStatus()
        wireTools()

        panels.start()
        lockScreen.start()
        updater.start()
        applySettings()
        applyNotchHidden()
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
        screenRecording.stop()
        ci.stop()
        micShortcut?.unregister()
        registeredMicShortcut = nil
        spectrum.isEnabled = false
        lowPower.stop()
        notes.flush()
        keepAwake.stop()
        cancelTimer()
        mirror.stop()
        lockScreen.stop()
        settings.setLockSessionOpen(false)
        panels.stop()
    }
}
