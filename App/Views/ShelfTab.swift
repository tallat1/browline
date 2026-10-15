import Integrations
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
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20))
                    Text("Dosyaları buraya sürükleyin")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                HStack {
                    Text("\(shelf.items.count) öğe")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("AirDrop") { ShelfStore.shareViaAirDrop(shelf.resolvedURLs) }
                    Button("Temizle") { shelf.clear() }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.white.opacity(isTargeted ? 0.8 : 0.2))
        }
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

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 36, height: 36)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 66)
        }
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
