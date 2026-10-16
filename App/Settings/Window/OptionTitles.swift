import AppKit
import Integrations
import NotchShell
import Observation
import ServiceManagement

extension PanelManager.ScreenPolicy {
    var title: String {
        switch self {
        // Kısa seçenek adları (ayar satırında kesilmesin); ayrıntı bölümün açıklamasında.
        case .builtInOrMain: String(localized: "Yalnız yerleşik ekran")
        case .allScreens: String(localized: "Tüm ekranlar")
        }
    }
}

extension HUDController.Mode {
    var title: String {
        switch self {
        case .off: String(localized: "Kapalı")
        case .overlay: String(localized: "Sistem göstergesine ek")
        case .replace: String(localized: "Sistem göstergesinin yerine")
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
