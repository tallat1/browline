import Integrations
import NotchShell
import SwiftUI

// MARK: - Göstergeler

struct IndicatorsPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .indicators) {
            Section("Kısa bildirimler") {
                Toggle("Şarkı değişince", isOn: $settings.trackPeekEnabled).settingsAnchor("trackPeek")
                Toggle("Ses çıkışı değişince", isOn: $settings.audioOutputAlertEnabled).settingsAnchor("audioOutput")
                Toggle("İndirme bitince", isOn: $settings.downloadsEnabled).settingsAnchor("downloads")
                if settings.downloadsEnabled {
                    PermissionRow(kind: .downloads, center: coordinator.permissions)
                }
            }
            Section("Gizlilik göstergeleri") {
                Toggle("Kamera ve mikrofon kullanımda", isOn: $settings.privacyIndicatorEnabled).settingsAnchor("privacy")
                Toggle("Ekran kaydediliyor ya da paylaşılıyor", isOn: $settings.screenRecordingIndicatorEnabled)
                    .settingsAnchor("screenRecording")
            }
            Section("Ses ve parlaklık") {
                Picker("Gösterge", selection: $settings.hudMode) {
                    ForEach(HUDController.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .settingsAnchor("hud")
                if settings.hudMode == .replace {
                    PermissionRow(kind: .accessibility, center: coordinator.permissions)
                    if !coordinator.hud.isBrightnessAvailable {
                        SettingsNote("Parlaklık bu Mac'te ayarlanamıyor; parlaklık tuşları sisteme bırakılır.")
                    }
                }
            }
        }
        .onAppear { coordinator.permissions.refresh() }
        .animation(.default, value: [settings.downloadsEnabled, settings.hudMode == .replace])
    }
}
