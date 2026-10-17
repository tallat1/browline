import Integrations
import NotchShell
import SwiftUI

// MARK: - Durum

struct StatusSettingsPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .status) {
            Section("Sistem") {
                Toggle("İşlemci, bellek ve ağ", isOn: $settings.systemStatsEnabled).settingsAnchor("system")
                ShowInNotchToggle(settings: settings, page: .system, isFeatureEnabled: settings.systemStatsEnabled)
            }
            Section("Bluetooth") {
                Toggle("Bluetooth aygıtları", isOn: $settings.bluetoothEnabled).settingsAnchor("bluetooth")
                SettingsNote("Bağlanınca, ayrılınca ve pil %20 ile %10'un altına inince kısa gösterge; Sistem sayfasında pil kartı.")
            }
            Section("Claude") {
                Toggle("Claude limitleri", isOn: $settings.claudeUsageEnabled).settingsAnchor("claude")
                ShowInNotchToggle(settings: settings, page: .claude, isFeatureEnabled: settings.claudeUsageEnabled)
                SettingsNote("Browline yüzdeleri kurulu Claude Code'a /usage sorarak okur; Claude Code kendi girişiyle yanıtlar, model kullanılmaz. Browline Claude girişinize hiç dokunmaz.")
            }
            Section("CI") {
                Toggle("GitHub Actions durumu", isOn: $settings.ciEnabled).settingsAnchor("ci")
                ShowInNotchToggle(settings: settings, page: .ci, isFeatureEnabled: settings.ciEnabled)
                if settings.ciEnabled {
                    CIRepositorySettings(settings: settings, ci: coordinator.ci)
                }
            }
        }
        .animation(.default, value: [settings.claudeUsageEnabled, settings.ciEnabled])
    }
}
