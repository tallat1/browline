import Integrations
import NotchShell
import SwiftUI

// MARK: - Şimdi

struct NowSettingsPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .now) {
            Section("Medya") {
                Toggle("Çalan müzik ve video", isOn: $settings.nowPlayingEnabled)
                    .settingsAnchor("media")
                SettingsNote("Spotify, Music, tarayıcı ve diğer oynatıcılar; birden çok oynatıcı varsa seçilebilir.")
                if settings.nowPlayingEnabled, coordinator.permissions.status(.automation) != .granted {
                    PermissionRow(kind: .automation, center: coordinator.permissions)
                }
            }
            Section("Toplantı") {
                Toggle("Mikrofonu sistem genelinde sessize alma", isOn: $settings.meetingControlsEnabled)
                    .settingsAnchor("meeting")
                if settings.meetingControlsEnabled {
                    Picker("Kısayol", selection: $settings.micShortcut) {
                        ForEach(GlobalShortcut.Preset.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .padding(.leading, 16)
                    .settingsAnchor("micShortcut")
                    if coordinator.ui.micShortcutUnavailable {
                        SettingsNote("Bu kısayol başka bir uygulamada kayıtlı; başka birini seçin.", tint: .red)
                    } else {
                        SettingsNote("Mikrofon kullanımdayken Şimdi'de kart; hangi uygulama öndeyse olsun kısayolla da.")
                    }
                }
            }
            Section("Claude Code") {
                ClaudeCodeConnectionRow(settings: settings)
            }
            Section("Dış etkinlikler") {
                Toggle("Betik ve AI ajanı etkinlikleri", isOn: $settings.activityAPIEnabled)
                    .settingsAnchor("activities")
                Toggle("Claude Code izin istemlerini notch'ta yanıtla", isOn: $settings.questionsEnabled)
                    .disabled(!settings.activityAPIEnabled)
                    .padding(.leading, 16)
                    .settingsAnchor("questions")
                Toggle("Claude'un seçenekli sorularını notch'ta yanıtla", isOn: $settings.choiceQuestionsEnabled)
                    .disabled(!settings.activityAPIEnabled)
                    .padding(.leading, 16)
                    .settingsAnchor("choiceQuestions")
                Toggle("Claude'un karar kutularını notch'ta göster", isOn: $settings.decisionCardsEnabled)
                    .disabled(!settings.activityAPIEnabled)
                    .padding(.leading, 16)
                    .settingsAnchor("decisionCards")
                Toggle("browline:// bağlantıları", isOn: $settings.urlSchemeEnabled)
                    .disabled(!settings.activityAPIEnabled)
                    .padding(.leading, 16)
                    .settingsAnchor("urlScheme")
                SettingsNote("Derleme ilerlemesi, Claude oturumları ve Kestirmeler Şimdi'de kart olarak görünür. Bağlantıları web sayfaları da açabilir; yalnız Raycast, Alfred ya da Kestirmeler'de kullanıyorsanız açın. Komut satırı ayrıntıları Gelişmiş'te.")
            }
        }
        .onAppear { coordinator.permissions.refresh() }
        .animation(.default, value: settings.meetingControlsEnabled)
    }
}
