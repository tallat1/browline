import Integrations
import NotchShell
import SwiftUI

// MARK: - Genel

struct GeneralSettingsPage: View {
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
            UpdatesSection(updater: coordinator.updater)
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

/// Güncellemeler: otomatik denetim (Sparkle'ın kendi ayarı) ve elle denetleme.
private struct UpdatesSection: View {
    @Bindable var updater: AppUpdater

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        Section {
            if AppUpdater.isAvailable {
                Toggle("Güncellemeleri otomatik denetle", isOn: $updater.automaticallyChecks)
                    .settingsAnchor("updates")
                HStack {
                    Text("Sürüm \(version)")
                    Spacer()
                    Button("Şimdi denetle") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            } else {
                SettingsNote("Debug derlemesinde güncelleme kapalı.")
                    .settingsAnchor("updates")
            }
        } header: {
            Text("Güncellemeler")
        } footer: {
            SettingsNote("Yeni sürümler GitHub'dan gelir ve imzaları doğrulanır. Denetimde yalnız sürüm listesi indirilir; kişisel bilgi gönderilmez.")
        }
        .onAppear { updater.refresh() }
    }
}
