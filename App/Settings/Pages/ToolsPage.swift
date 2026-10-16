import Integrations
import NotchShell
import SwiftUI

// MARK: - Araçlar

struct ToolsPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .tools) {
            Section("Not") {
                Toggle("Hızlı not", isOn: $settings.notesEnabled).settingsAnchor("notes")
                ShowInNotchToggle(settings: settings, tab: .notes, isFeatureEnabled: settings.notesEnabled)
            }
            Section("Zamanlayıcı") {
                Toggle("Zamanlayıcı ve Pomodoro", isOn: $settings.timerEnabled).settingsAnchor("timer")
                ShowInNotchToggle(settings: settings, tab: .timer, isFeatureEnabled: settings.timerEnabled)
            }
            Section("Terminal") {
                Toggle("Terminal", isOn: $settings.terminalEnabled).settingsAnchor("terminal")
                ShowInNotchToggle(settings: settings, tab: .terminal, isFeatureEnabled: settings.terminalEnabled)
                SettingsNote("Kapatınca açık kabuk sonlanır.")
            }
            Section("Ayna") {
                Toggle("Ayna", isOn: $settings.mirrorEnabled).settingsAnchor("mirror")
                ShowInNotchToggle(settings: settings, tab: .mirror, isFeatureEnabled: settings.mirrorEnabled)
                if settings.mirrorEnabled {
                    PermissionRow(kind: .camera, center: coordinator.permissions)
                }
            }
        }
        .onAppear { coordinator.permissions.refresh() }
        .animation(.default, value: settings.mirrorEnabled)
    }
}
