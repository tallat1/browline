import Integrations
import NotchShell
import SwiftUI

// MARK: - Genel

struct GeneralPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .general) {
            Section("Başlangıç") {
                Toggle("Girişte başlat", isOn: Binding(get: { settings.launchAtLogin },
                                                       set: { settings.launchAtLogin = $0 }))
                    .settingsAnchor("launchAtLogin")
                if settings.launchAtLoginStatus == .requiresApproval {
                    SettingsNote("Sistem Ayarları › Genel › Giriş Öğeleri'nden onay gerekiyor.")
                }
                HStack {
                    Text("Karşılama")
                    Spacer()
                    Button("Yeniden göster") { coordinator.openOnboarding?() }
                }
                .settingsAnchor("onboarding")
            }
            Section {
                let displays = PanelManager.displaySummaries(for: settings.panelOptions)
                ForEach(displays) { display in
                    Picker(display.name, selection: Binding(
                        get: { display.mode },
                        set: { settings.displayModes[display.persistentID] = $0 })) {
                        ForEach(PanelManager.DisplayMode.allCases, id: \.self) {
                            Text($0.title(hasNotch: display.hasNotch)).tag($0)
                        }
                    }
                }
                Picker("Sonradan takılan ekranlar", selection: $settings.screenPolicy) {
                    ForEach(PanelManager.ScreenPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if displays.contains(where: { $0.mode == .automatic && !$0.hasNotch }) {
                    Picker("Çentiksiz ekranlarda hap", selection: $settings.notchlessVisibility) {
                        ForEach(PanelManager.NotchlessVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("Ekranlar").settingsAnchor("displays")
            } footer: {
                SettingsNote("Seçim ekrana bağlı saklanır; çıkarıp takınca korunur. Çentiksiz ekranda hap, istenirse menü çubuğunun altında yüzen kart görünür.")
            }
        }
    }
}
