import Integrations
import NotchShell
import SwiftUI
import UniformTypeIdentifiers

/// Dosya rafı: notch'a sürüklenen dosyalar burada durur, buradan başka yere sürüklenir
/// ya da AirDrop ile gönderilir. Özgün dosyaya bookmark ile başvurur, kopyalamaz.
struct ShelfTab: View {
    let shelf: ShelfStore
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shelf.items.isEmpty {
                EmptyStateView(symbol: "tray.and.arrow.down", title: "Dosyaları buraya sürükleyin",
                               message: "Raftan başka yere sürükleyin ya da AirDrop ile gönderin.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf).notchTransition(.swap)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                HStack(spacing: 6) {
                    Text("\(shelf.items.count) öğe")
                        .font(NotchDesign.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("AirDrop") { ShelfStore.shareViaAirDrop(shelf.resolvedURLs) }
                        .buttonStyle(CapsuleButtonStyle())
                    Button("Temizle") { shelf.clear() }
                        .buttonStyle(CapsuleButtonStyle())
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous)
                .fill(isTargeted ? NotchDesign.cardHoverFill : NotchDesign.cardFill)
            RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.white.opacity(isTargeted ? 0.7 : 0.15))
        }
        .notchAnimation(NotchMotion.hover, value: isTargeted)
        // Rafa dosya eklenince/kaldırılınca öğeler ve boş durum geçişle.
        .notchAnimation(value: shelf.items.map(\.id))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { shelf.add([url]) }
                    }
                }
            }
            return true
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfStore.Item
    let shelf: ShelfStore
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 36, height: 36)
            Text(item.name)
                .font(NotchDesign.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 66)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isHovering ? NotchDesign.cardHoverFill : .clear))
        .onHover { isHovering = $0 }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: (shelf.resolvedURL(for: item) ?? item.url) as NSURL)
        }
        .contextMenu {
            Button("Finder'da göster") {
                if let url = shelf.resolvedURL(for: item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("AirDrop ile gönder") {
                if let url = shelf.resolvedURL(for: item) { ShelfStore.shareViaAirDrop([url]) }
            }
            Divider()
            Button("Raftan kaldır") { shelf.remove(item.id) }
        }
        .help(item.url.path)
    }
}
