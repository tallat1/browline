import Integrations
import NotchShell
import SwiftUI

/// Bir ayar sayfasının iskeleti: başlık + gruplu form. Satırlar `settingsAnchor` ile aranabilir.
struct SettingsForm<Content: View>: View {
    let page: SettingsPage
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            // Başlık bir satır olarak (zeminsiz): boş bölümün başlığı olunca ilk grup başlığı farklı çiziliyordu.
            Section {
                SettingsPageHeader(page: page)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            content
        }
        .formStyle(.grouped)
    }
}
