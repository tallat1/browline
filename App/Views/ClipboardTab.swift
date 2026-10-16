import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Pano geçmişi: son kopyalananlar. Satıra basınca yeniden panoya kopyalanır (ardından ⌘V). Üzerine
/// gelince sabitle ve sil. Yalnız bellekte; parola yöneticilerinin gizli kopyaları hiç alınmaz.
struct ClipboardTab: View {
    let history: ClipboardHistory
    @State private var copiedID: UUID?

    var body: some View {
        ZStack {
            content
                .id(history.items.isEmpty)
                .notchTransition(.swap)
        }
        .notchAnimation(value: history.items.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if history.isReadingBlocked {
            EmptyStateView(symbol: "hand.raised", title: "Pano okuma engellenmiş",
                           message: "Gizlilik ve Güvenlik › Diğer uygulamalardan yapıştırma'dan Browline'a izin verin.")
        } else if history.items.isEmpty {
            EmptyStateView(symbol: "doc.on.clipboard", title: "Henüz kopyalanan bir şey yok",
                           message: "Kopyaladığın metin, bağlantı, dosya ve görseller burada görünür; basınca yeniden kopyalanır.")
        } else {
            VStack(alignment: .leading, spacing: NotchDesign.Space.s) {
                HStack {
                    CardLabel("Son kopyalananlar")
                    Spacer()
                    Button("Temizle") { history.clear() }
                        .buttonStyle(QuietButtonStyle())
                        .help("Sabitlenmemiş öğeleri siler")
                }
                ScrollView {
                    LazyVStack(spacing: NotchDesign.Space.xxs) {
                        ForEach(history.items) { item in
                            ClipRow(item: item, isCopied: copiedID == item.id,
                                    copy: {
                                        history.copy(item.id)
                                        copiedID = history.items.first?.id
                                    },
                                    togglePin: { history.togglePin(item.id) },
                                    remove: { history.remove(item.id) })
                                .notchTransition(.listItem)
                        }
                    }
                    .notchAnimation(value: history.items.map(\.id))
                }
                .scrollIndicators(.never)
            }
            .task(id: copiedID) {
                // "Kopyalandı" işareti kısa süre kalır.
                guard copiedID != nil else { return }
                try? await Task.sleep(for: .seconds(1.5))
                copiedID = nil
            }
        }
    }
}

private struct ClipRow: View {
    let item: ClipboardHistory.Item
    let isCopied: Bool
    let copy: () -> Void
    let togglePin: () -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NotchDesign.Space.m + 2) {
            leading
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: NotchDesign.Radius.small - 1, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.preview)
                    .font(NotchDesign.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TimelineView(.everyMinute) { timeline in
                    Text(verbatim: meta(now: timeline.currentDate))
                        .font(NotchDesign.caption)
                        .foregroundStyle(NotchDesign.metadata)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: NotchDesign.Space.s)
            if isCopied {
                Label("Kopyalandı", systemImage: "checkmark")
                    .labelStyle(MetadataLabelStyle())
                    .font(NotchDesign.captionEmphasized)
                    .foregroundStyle(.green)
                    .notchTransition(.fade)
            } else if isHovering || item.isPinned {
                HStack(spacing: 0) {
                    Button(action: togglePin) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: NotchDesign.Icon.small, weight: NotchDesign.Icon.weight))
                            .foregroundStyle(item.isPinned ? .orange : .secondary)
                    }
                    .buttonStyle(IconButtonStyle(size: NotchDesign.Control.small))
                    .help(item.isPinned ? "Sabitlemeyi kaldır" : "Sabitle (temizlemede silinmez)")
                    if isHovering {
                        Button(action: remove) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(IconButtonStyle(size: NotchDesign.Control.small))
                        .help("Geçmişten sil")
                    }
                }
                .notchTransition(.fade)
            }
        }
        .padding(.horizontal, NotchDesign.Space.m)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: NotchDesign.Radius.small, style: .continuous)
            .fill(isHovering ? NotchDesign.cardHoverFill : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: copy)
        .onHover { isHovering = $0 }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .notchAnimation(value: isCopied)
        .help("Basınca panoya kopyalanır")
    }

    @ViewBuilder
    private var leading: some View {
        switch item.content {
        case let .image(data, _):
            if let image = ClipThumbnails.image(for: item.id, data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                symbol("photo")
            }
        case let .files(urls):
            Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path)).resizable()
        case .url:
            symbol("link")
        case .text:
            symbol("text.alignleft")
        }
    }

    private func symbol(_ name: String) -> some View {
        ZStack {
            NotchDesign.cardFill
            Image(systemName: name)
                .font(.system(size: NotchDesign.Icon.regular, weight: NotchDesign.Icon.weight))
                .foregroundStyle(.secondary)
        }
    }

    private func meta(now: Date) -> String {
        let app = item.sourceBundleIdentifier.flatMap(MediaTab.appName(for:))
        let minutes = Int(now.timeIntervalSince(item.copiedAt) / 60)
        let when = minutes < 1 ? String(localized: "az önce")
            : (minutes < 60 ? String(localized: "\(minutes) dk önce")
               : item.copiedAt.formatted(date: .omitted, time: .shortened))
        return [app, when].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Görsel küçük resimleri önbellekte: her çizimde veri yeniden çözülmez.
@MainActor
private enum ClipThumbnails {
    private static var cache: [UUID: NSImage] = [:]

    static func image(for id: UUID, data: Data) -> NSImage? {
        if let cached = cache[id] { return cached }
        guard let image = NSImage(data: data) else { return nil }
        if cache.count > 60 { cache.removeAll() }
        cache[id] = image
        return image
    }
}
