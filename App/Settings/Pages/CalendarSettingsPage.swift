import Integrations
import NotchShell
import SwiftUI

// MARK: - Takvim

struct CalendarSettingsPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .calendar) {
            Section("Takvim") {
                Toggle("Takvim ve toplantılar", isOn: $settings.calendarEnabled)
                    .settingsAnchor("calendar")
                ShowInNotchToggle(settings: settings, page: .calendar, isFeatureEnabled: settings.calendarEnabled)
                if settings.calendarEnabled {
                    PermissionRow(kind: .calendar, center: coordinator.permissions)
                }
            }
            Section("Anımsatıcılar") {
                Toggle("Bugünün anımsatıcıları", isOn: $settings.remindersEnabled)
                    .disabled(!settings.calendarEnabled)
                    .settingsAnchor("reminders")
                if settings.calendarEnabled, settings.remindersEnabled {
                    PermissionRow(kind: .reminders, center: coordinator.permissions)
                }
                SettingsNote("Takvim sayfasının sağ sütununda; daireye basınca tamamlanır.")
            }
        }
        .onAppear { coordinator.permissions.refresh() }
        .animation(.default, value: [settings.calendarEnabled, settings.remindersEnabled])
    }
}
