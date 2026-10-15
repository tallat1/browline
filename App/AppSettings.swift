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
    var openDelayMilliseconds: Int { didSet { store(openDelayMilliseconds, "openDelayMilliseconds") } }
    var hapticsEnabled: Bool { didSet { store(hapticsEnabled, "hapticsEnabled") } }
    var hideInFullScreen: Bool { didSet { store(hideInFullScreen, "hideInFullScreen") } }
    var hideFromScreenCapture: Bool { didSet { store(hideFromScreenCapture, "hideFromScreenCapture") } }
    var nowPlayingEnabled: Bool { didSet { store(nowPlayingEnabled, "nowPlayingEnabled") } }
    var batteryEnabled: Bool { didSet { store(batteryEnabled, "batteryEnabled") } }
    var calendarEnabled: Bool { didSet { store(calendarEnabled, "calendarEnabled") } }
    var shelfEnabled: Bool { didSet { store(shelfEnabled, "shelfEnabled") } }
    var activityAPIEnabled: Bool { didSet { store(activityAPIEnabled, "activityAPIEnabled") } }
    var hudMode: HUDController.Mode { didSet { store(hudMode.rawValue, "hudMode") } }
    var privacyIndicatorEnabled: Bool { didSet { store(privacyIndicatorEnabled, "privacyIndicatorEnabled") } }
    /// İndirilenler klasörü TCC korumalı; kullanıcı açana kadar erişilmez.
    var downloadsEnabled: Bool { didSet { store(downloadsEnabled, "downloadsEnabled") } }
    var hasCompletedOnboarding: Bool { didSet { store(hasCompletedOnboarding, "hasCompletedOnboarding") } }

    /// Giriş öğesi durumu sistemde tutulur; burada yalnız yansıtılır.
    private(set) var launchAtLoginStatus: SMAppService.Status = SMAppService.mainApp.status

    @ObservationIgnored var onChange: (() -> Void)?

    static let openDelayChoices = [0, 150, 300, 500]

    init() {
        let defaults = UserDefaults.standard
        screenPolicy = PanelManager.ScreenPolicy(rawValue: defaults.string(forKey: "screenPolicy") ?? "")
            ?? .builtInOrMain
        openDelayMilliseconds = defaults.object(forKey: "openDelayMilliseconds") as? Int ?? 150
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        hideInFullScreen = defaults.bool(forKey: "hideInFullScreen")
        hideFromScreenCapture = defaults.bool(forKey: "hideFromScreenCapture")
        nowPlayingEnabled = defaults.object(forKey: "nowPlayingEnabled") as? Bool ?? true
        batteryEnabled = defaults.object(forKey: "batteryEnabled") as? Bool ?? true
        calendarEnabled = defaults.object(forKey: "calendarEnabled") as? Bool ?? true
        shelfEnabled = defaults.object(forKey: "shelfEnabled") as? Bool ?? true
        activityAPIEnabled = defaults.object(forKey: "activityAPIEnabled") as? Bool ?? true
        hudMode = HUDController.Mode(rawValue: defaults.string(forKey: "hudMode") ?? "") ?? .off
        privacyIndicatorEnabled = defaults.object(forKey: "privacyIndicatorEnabled") as? Bool ?? true
        downloadsEnabled = defaults.bool(forKey: "downloadsEnabled")
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }

    var panelOptions: PanelManager.Options {
        var options = PanelManager.Options()
        options.screenPolicy = screenPolicy
        options.openDelay = .milliseconds(openDelayMilliseconds)
        options.hapticsEnabled = hapticsEnabled
        options.hideInFullScreen = hideInFullScreen
        options.hideFromScreenCapture = hideFromScreenCapture
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
        case .builtInOrMain: "Yalnız yerleşik ekran (kapak kapalıysa ana ekran)"
        case .allScreens: "Tüm ekranlar (çentiksiz ekranda hap)"
        }
    }
}

extension HUDController.Mode {
    var title: String {
        switch self {
        case .off: "Kapalı"
        case .overlay: "Ek gösterge (izin gerekmez; sistem göstergesi de görünür)"
        case .replace: "Sistem göstergesinin yerine geç (Erişilebilirlik izni)"
        }
    }
}
