import Integrations
import NotchShell
import SwiftUI

/// Hızlı not (NotchPad, Islet). Sekme görünürken panel key olabilir; klavye yalnız alana tıklayınca
/// alınır. Yazmaya başlayınca notch sabitlenir, imleç çıkınca kapanmaz; Esc ya da dışarı tıklama kapatır.
struct NotesTab: View {
    let notes: NotesStore
    let model: NotchSurfaceModel
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var notes = notes
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes.text)
                .font(NotchDesign.body)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
            if notes.text.isEmpty {
                Text("Not alın… (tıklayıp yazın; ⌘C, ⌘V çalışır)")
                    .font(NotchDesign.body)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous).fill(NotchDesign.cardFill))
        .overlay(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous)
            .strokeBorder(NotchDesign.hairline, lineWidth: 0.5))
        .onAppear { model.wantsKeyboard = true }
        .onDisappear {
            model.wantsKeyboard = false
            notes.flush()
        }
        .onChange(of: isFocused) { _, focused in
            if focused { model.tapped() }
        }
    }
}
