import Integrations
import NotchShell
import SwiftUI

// MARK: - Gelişmiş

struct AdvancedSettingsPage: View {
    let coordinator: AppCoordinator

    var body: some View {
        SettingsForm(page: .advanced) {
            Section {
                LabeledContent("Durum") {
                    Text(coordinator.ui.activityAPIStatus).textSelection(.enabled)
                }
                HStack {
                    Text(coordinator.cliPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Yolu kopyala") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(coordinator.cliPath, forType: .string)
                    }
                }
            } header: {
                Text("Etkinlik API'si ve notch komutu").settingsAnchor("api")
            } footer: {
                SettingsNote("Betikler, AI ajanları ve Kestirmeler (Kabuk Betiği Çalıştır) yerel soketle etkinlik gönderir: notch push --id build --title Derleme --progress 40%. Yalnız sizin kullanıcınız bağlanabilir.")
            }
            Section {
                LabeledContent("Kaynak") { Text(verbatim: coordinator.nowPlayingSourceDescription).textSelection(.enabled) }
            } header: {
                Text("Medya kaynağı").settingsAnchor("source")
            } footer: {
                SettingsNote("Sistem geneli Now Playing macOS 15.4'ten beri public değil; mediaremote-adapter kullanılıyor. Çalışmazsa yalnız Music ve Spotify, AppleScript ile.")
            }
            Section {
                LabeledContent("Kilit ekranı paneli", value: "SkyLight")
                LabeledContent("Parlaklık", value: "DisplayServices")
                LabeledContent("Ekran kaydı göstergesi", value: "CGSIsScreenWatcherPresent")
                LabeledContent("Claude yüzdeleri", value: "api.anthropic.com/api/oauth/usage")
            } header: {
                Text("Belgelenmemiş macOS işlevleri").settingsAnchor("private")
            } footer: {
                SettingsNote("Bunlar çalışma anında aranır; bulunamazsa ilgili özellik kapanır, uygulama çökmez.")
            }
        }
    }
}
