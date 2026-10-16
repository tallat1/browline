import Integrations
import NotchShell
import SwiftUI

// MARK: - Kilit ekranı

struct LockScreenPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .lockScreen) {
            Section {
                Toggle("Müzik ve pil şeridi", isOn: $settings.lockScreenWidgetsEnabled).settingsAnchor("lockWidgets")
                SettingsNote("Kilitliyken notch genişler: solda çalan şarkı, sağda pil. Tıklanamaz; macOS'un saatini örtmez.")
            }
            Section {
                Toggle("Kilit ekranında ayrı panel (deneysel)", isOn: $settings.lockScreenEnabled).settingsAnchor("lockScreen")
                SettingsNote("Yalnız müzik, şarj, kamera/mikrofon ve ses göstergesi görünür; raf, takvim ve dış etkinlikler görünmez. Bir sorun oturumu kapatabilir.")
                if settings.lockScreenAutoDisabled {
                    SettingsNote("Önceki kilit sırasında uygulama beklenmedik biçimde kapandı; özellik güvenlik için kapatıldı.", tint: .orange)
                }
                switch coordinator.lockScreen.status {
                case .unavailable:
                    SettingsNote("Bu macOS sürümünde kullanılamıyor.", tint: .orange)
                case .failed:
                    SettingsNote("Kilit ekranı alanı kurulamadı; özellik bu oturumda çalışmıyor.", tint: .orange)
                case .off, .ready:
                    EmptyView()
                }
            }
        }
    }
}
