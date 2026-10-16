import Integrations
import NotchShell
import SwiftUI

// MARK: - Raf

struct ShelfPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .shelf) {
            Section("Dosyalar") {
                Toggle("Dosya rafı", isOn: $settings.shelfEnabled)
                    .settingsAnchor("shelf")
                ShowInNotchToggle(settings: settings, tab: .shelf, isFeatureEnabled: settings.shelfEnabled)
                SettingsNote("Ekran görüntüsü küçük resimleri \(ShelfStore.promiseDestination().lastPathComponent) klasörüne kaydedilir. Rafta \(coordinator.shelf.items.count) öğe.")
            }
            Section("Pano geçmişi") {
                Toggle("Pano geçmişi", isOn: $settings.clipboardEnabled)
                    .settingsAnchor("clipboard")
                ShowInNotchToggle(settings: settings, tab: .clipboard, isFeatureEnabled: settings.clipboardEnabled)
                SettingsNote("Son 50 kopya, yalnız bellekte. Parola yöneticilerinin gizli kopyaları alınmaz.")
            }
        }
    }
}
