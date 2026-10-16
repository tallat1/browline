import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Ayrıntı sayfasının başı: bölüme dönüş ve sayfa adı (ör. "‹ Şimdi · Etkinlikler").
struct DetailHeader: View {
    let title: String
    let back: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: NotchDesign.Space.xs) {
            Button(action: action) {
                Label(back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
            }
            .buttonStyle(QuietButtonStyle())
            .help("\(back)'ye dön")
            Text(verbatim: "·").foregroundStyle(.tertiary)
            Text(verbatim: title).font(NotchDesign.captionEmphasized)
            Spacer()
        }
        .frame(height: NotchDesign.Control.small)
    }
}
