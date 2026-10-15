import AppKit
import Integrations
import NotchShell
import Observation
import ServiceManagement

/// Kalıcı ayarlar (UserDefaults). Değişiklik koordinatöre onChange ile bildirilir.
@MainActor
@Observable
final class AppSettings {
    var screenPolicy: PanelManager.ScreenPolicy { didSet { store(screenPolicy.rawValue, "screenPolicy") } }
    var notchlessVisibility: PanelManager.NotchlessVisibility {
        didSet { store(notchlessVisibility.rawValue, "notchlessVisibility") }
    }
    var openDelayMilliseconds: Int { didSet { store(openDelayMilliseconds, "openDelayMilliseconds") } }
    var hapticsEnabled: Bool { didSet { store(hapticsEnabled, "hapticsEnabled") } }
    var hideInFullScreen: Bool { didSet { store(hideInFullScreen, "hideInFullScreen") } }
    var hideFromScreenCapture: Bool { didSet { store(hideFromScreenCapture, "hideFromScreenCapture") } }
    /// Kalıcı ekran kimliği → mod; seçim yapılmamış ekran `screenPolicy`'den varsayılan alır.
    var displayModes: [String: PanelManager.DisplayMode] {
        didSet { store(displayModes.mapValues(\.rawValue), "displayModes") }
    }
    var hideInMissionControl: Bool { didSet { store(hideInMissionControl, "hideInMissionControl") } }
    var hideInGames: Bool { didSet { store(hideInGames, "hideInGames") } }
    var nowPlayingEnabled: Bool { didSet { store(nowPlayingEnabled, "nowPlayingEnabled") } }
    var batteryEnabled: Bool { didSet { store(batteryEnabled, "batteryEnabled") } }
    var calendarEnabled: Bool { didSet { store(calendarEnabled, "calendarEnabled") } }
    var shelfEnabled: Bool { didSet { store(shelfEnabled, "shelfEnabled") } }
    var activityAPIEnabled: Bool { didSet { store(activityAPIEnabled, "activityAPIEnabled") } }
    var hudMode: HUDController.Mode { didSet { store(hudMode.rawValue, "hudMode") } }
    var privacyIndicatorEnabled: Bool { didSet { store(privacyIndicatorEnabled, "privacyIndicatorEnabled") } }
    /// İndirilenler klasörü TCC korumalı; kullanıcı açana kadar erişilmez.
    var downloadsEnabled: Bool { didSet { store(downloadsEnabled, "downloadsEnabled") } }
    var trackPeekEnabled: Bool { didSet { store(trackPeekEnabled, "trackPeekEnabled") } }
    var audioOutputAlertEnabled: Bool { didSet { store(audioOutputAlertEnabled, "audioOutputAlertEnabled") } }
    var keepAwakeEnabled: Bool { didSet { store(keepAwakeEnabled, "keepAwakeEnabled") } }
    var timerEnabled: Bool { didSet { store(timerEnabled, "timerEnabled") } }
    /// Takvim sekmesinde; izin yalnız düğmeye basınca istenir.
    var remindersEnabled: Bool { didSet { store(remindersEnabled, "remindersEnabled") } }
    var systemStatsEnabled: Bool { didSet { store(systemStatsEnabled, "systemStatsEnabled") } }
    /// Kamera izni yalnız Ayna sekmesinde düğmeye basınca istenir.
    var mirrorEnabled: Bool { didSet { store(mirrorEnabled, "mirrorEnabled") } }
    var hasCompletedOnboarding: Bool { didSet { store(hasCompletedOnboarding, "hasCompletedOnboarding") } }
    /// Kilit ekranı private SkyLight kullanır; varsayılan kapalı.
    var lockScreenEnabled: Bool {
        didSet {
            if lockScreenEnabled { lockScreenAutoDisabled = false }
            store(lockScreenEnabled, "lockScreenEnabled")
        }
    }
    /// Önceki kilit kapanmadan uygulama sonlandıysa (çökme, WindowServer, zorla kapatma) özellik
    /// kendiliğinden kapatılır; çökme döngüsüne girmemek için. Ayarlarda neden gösterilir.
    private(set) var lockScreenAutoDisabled: Bool {
        didSet { UserDefaults.standard.set(lockScreenAutoDisabled, forKey: "lockScreenAutoDisabled") }
    }

    /// Giriş öğesi durumu sistemde tutulur; burada yalnız yansıtılır.
    private(set) var launchAtLoginStatus: SMAppService.Status = SMAppService.mainApp.status

    @ObservationIgnored var onChange: (() -> Void)?

    static let openDelayChoices = [0, 150, 300, 500]

    init() {
        let defaults = UserDefaults.standard
        screenPolicy = PanelManager.ScreenPolicy(rawValue: defaults.string(forKey: "screenPolicy") ?? "")
            ?? .builtInOrMain
        notchlessVisibility = PanelManager.NotchlessVisibility(
            rawValue: defaults.string(forKey: "notchlessVisibility") ?? "") ?? .always
        openDelayMilliseconds = defaults.object(forKey: "openDelayMilliseconds") as? Int ?? 150
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        hideInFullScreen = defaults.bool(forKey: "hideInFullScreen")
        hideFromScreenCapture = defaults.bool(forKey: "hideFromScreenCapture")
        displayModes = (defaults.dictionary(forKey: "displayModes") as? [String: String] ?? [:])
            .compactMapValues(PanelManager.DisplayMode.init(rawValue:))
        hideInMissionControl = defaults.bool(forKey: "hideInMissionControl")
        hideInGames = defaults.bool(forKey: "hideInGames")
        nowPlayingEnabled = defaults.object(forKey: "nowPlayingEnabled") as? Bool ?? true
        batteryEnabled = defaults.object(forKey: "batteryEnabled") as? Bool ?? true
        calendarEnabled = defaults.object(forKey: "calendarEnabled") as? Bool ?? true
        shelfEnabled = defaults.object(forKey: "shelfEnabled") as? Bool ?? true
        activityAPIEnabled = defaults.object(forKey: "activityAPIEnabled") as? Bool ?? true
        hudMode = HUDController.Mode(rawValue: defaults.string(forKey: "hudMode") ?? "") ?? .off
        privacyIndicatorEnabled = defaults.object(forKey: "privacyIndicatorEnabled") as? Bool ?? true
        downloadsEnabled = defaults.bool(forKey: "downloadsEnabled")
        trackPeekEnabled = defaults.object(forKey: "trackPeekEnabled") as? Bool ?? true
        audioOutputAlertEnabled = defaults.object(forKey: "audioOutputAlertEnabled") as? Bool ?? true
        keepAwakeEnabled = defaults.object(forKey: "keepAwakeEnabled") as? Bool ?? true
        timerEnabled = defaults.object(forKey: "timerEnabled") as? Bool ?? true
        remindersEnabled = defaults.object(forKey: "remindersEnabled") as? Bool ?? true
        systemStatsEnabled = defaults.object(forKey: "systemStatsEnabled") as? Bool ?? true
        mirrorEnabled = defaults.object(forKey: "mirrorEnabled") as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        if defaults.bool(forKey: Self.lockSessionKey), defaults.bool(forKey: "lockScreenEnabled") {
            defaults.set(false, forKey: "lockScreenEnabled")
            defaults.set(true, forKey: "lockScreenAutoDisabled")
        }
        defaults.removeObject(forKey: Self.lockSessionKey)
        lockScreenEnabled = defaults.bool(forKey: "lockScreenEnabled")
        lockScreenAutoDisabled = defaults.bool(forKey: "lockScreenAutoDisabled")
    }

    private static let lockSessionKey = "lockScreenSessionOpen"

    /// Kilit paneli SkyLight Space'indeyken true. Kilit açılınca ya da düzgün çıkışta silinir;
    /// açılışta hâlâ duruyorsa önceki kilit yarıda kalmıştır.
    func setLockSessionOpen(_ open: Bool) {
        if open {
            UserDefaults.standard.set(true, forKey: Self.lockSessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lockSessionKey)
        }
    }

    var panelOptions: PanelManager.Options {
        var options = PanelManager.Options()
        options.screenPolicy = screenPolicy
        options.notchlessVisibility = notchlessVisibility
        options.openDelay = .milliseconds(openDelayMilliseconds)
        options.hapticsEnabled = hapticsEnabled
        options.hideInFullScreen = hideInFullScreen
        options.hideFromScreenCapture = hideFromScreenCapture
        options.displayModes = displayModes
        options.hideInMissionControl = hideInMissionControl
        options.hideInGames = hideInGames
        options.detectsFileDrags = shelfEnabled
        return options
    }

    var launchAtLogin: Bool {
        get { launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Giriş öğesi değiştirilemedi: \(error.localizedDescription)")
            }
            launchAtLoginStatus = SMAppService.mainApp.status
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        onChange?()
    }
}

extension PanelManager.ScreenPolicy {
    var title: String {
        switch self {
        case .builtInOrMain: String(localized: "Yalnız yerleşik ekran (kapak kapalıysa ana ekran)")
        case .allScreens: String(localized: "Tüm ekranlar (çentiksiz ekranda hap)")
        }
    }
}

extension HUDController.Mode {
    var title: String {
        switch self {
        case .off: String(localized: "Kapalı")
        case .overlay: String(localized: "Ek gösterge (izin gerekmez; sistem göstergesi de görünür)")
        case .replace: String(localized: "Sistem göstergesinin yerine geç (Erişilebilirlik izni)")
        }
    }
}

extension PanelManager.DisplayMode {
    func title(hasNotch: Bool) -> String {
        switch self {
        case .automatic: hasNotch ? String(localized: "Çentik") : String(localized: "Hap (menü çubuğunda)")
        case .floating: String(localized: "Yüzen kart (menü çubuğunun altında)")
        case .off: String(localized: "Kapalı")
        }
    }
}

extension PanelManager.NotchlessVisibility {
    var title: String {
        switch self {
        case .always: String(localized: "Her zaman")
        case .whenActive: String(localized: "Yalnız gösterecek bir etkinlik varken")
        }
    }
}
