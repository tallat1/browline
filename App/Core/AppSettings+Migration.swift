import AppKit
import Integrations
import NotchShell
import Observation
import ServiceManagement

extension AppSettings {
    /// 0.9.0'da açık gelen geliştirici ve toplantı özellikleri karşılamanın varsayılan profiline (medya + dosyalar)
    /// çekildi: karşılama bitmeden ya da "Atla" ile hiçbiri arka planda çalışmasın. Karşılamayı geçmiş kurulumda
    /// hiç yazılmamış anahtar eski varsayılanıyla (açık) yazılır; mevcut kullanıcının gördüğü değişmez.
    static let defaultsVersion = 2
    static let previouslyOnByDefault = ["calendarEnabled", "remindersEnabled", "meetingControlsEnabled", "privacyIndicatorEnabled", "screenRecordingIndicatorEnabled", "terminalEnabled", "ciEnabled", "claudeUsageEnabled", "activityAPIEnabled", "questionsEnabled", "systemStatsEnabled"]

    static func migrateDefaults(_ defaults: UserDefaults) {
        guard defaults.integer(forKey: "settingsDefaultsVersion") < defaultsVersion else { return }
        if defaults.bool(forKey: "hasCompletedOnboarding") {
            // URL şeması eskiden etkinlik API'siyle birlikte açıktı.
            if defaults.object(forKey: "urlSchemeEnabled") == nil {
                defaults.set(defaults.object(forKey: "activityAPIEnabled") as? Bool ?? true, forKey: "urlSchemeEnabled")
            }
            for key in previouslyOnByDefault where defaults.object(forKey: key) == nil {
                defaults.set(true, forKey: key)
            }
        }
        // 0.9.0: Claude oturum anahtarıyla kullanım sorgusu kaldırıldı (Anthropic kuralları); ayarı kalmasın.
        defaults.removeObject(forKey: "claudeUsageAPIEnabled")
        defaults.set(defaultsVersion, forKey: "settingsDefaultsVersion")
    }
}
