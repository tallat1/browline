import Integrations
import NotchShell
import SwiftUI
import UniformTypeIdentifiers

/// Dosya rafı: notch'a sürüklenen dosyalar burada durur, buradan başka yere sürüklenir, paylaşılır,
/// sıkıştırılır, dönüştürülür ya da önizlenir. Özgün dosyaya bookmark ile başvurur, kopyalamaz.
struct ShelfTab: View {
    let shelf: ShelfStore
    /// Bırakılabilir bir şey notch'un üstünde. Bırakma AppKit katmanında (`FileDropView`): dosya sözleri
    /// (ekran görüntüsü küçük resmi) SwiftUI `onDrop` ile alınamıyordu.
    let isTargeted: Bool
    @State private var isCompressing = false
    /// Dönüştürülmekte olan öğeler (karo üstünde ilerleme).
    @State private var converting: Set<ShelfStore.Item.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shelf.items.isEmpty {
                EmptyStateView(symbol: "tray.and.arrow.down", title: "Dosyaları buraya sürükleyin",
                               message: "Raftan başka yere sürükleyin, paylaşın, sıkıştırın ya da önizleyin.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf, isConverting: converting.contains(item.id),
                                      compress: compress, convert: { convert(item, $0, $1) })
                                .notchTransition(.swap)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                HStack(spacing: NotchDesign.Space.s) {
                    Text("\(shelf.items.count) öğe")
                        .font(NotchDesign.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Sistem paylaşım menüsü: AirDrop, Mesajlar, Mail, Notlar…
                    ShareLink(items: shelf.resolvedURLs) {
                        Label("Paylaş", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(CapsuleButtonStyle())
                    Button {
                        compress(shelf.resolvedURLs)
                    } label: {
                        Label(isCompressing ? "Sıkıştırılıyor…" : "Sıkıştır", systemImage: "doc.zipper")
                    }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(isCompressing)
                    .help("Raftaki her şeyi tek zip'te toplar (İndirilenler)")
                    Button("Temizle") { shelf.clear() }
                        .buttonStyle(QuietButtonStyle())
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
        .notchAnimation(value: isCompressing)
    }

    /// Sonuç kaynağın yanına yazılır ve rafa eklenir; başarısızsa uyarı sesi.
    private func convert(_ item: ShelfStore.Item, _ url: URL, _ conversion: ShelfConversion) {
        guard !converting.contains(item.id) else { return }
        converting.insert(item.id)
        ShelfConverter.convert(url, conversion) { result in
            converting.remove(item.id)
            if let result { shelf.add([result]) } else { NSSound.beep() }
        }
    }

    /// Sonuç rafa da eklenir: arşiv hemen sürüklenip paylaşılabilsin.
    private func compress(_ urls: [URL]) {
        guard !urls.isEmpty, !isCompressing else { return }
        isCompressing = true
        ShelfStore.compress(urls) { archive in
            isCompressing = false
            if let archive { shelf.add([archive]) }
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfStore.Item
    let shelf: ShelfStore
    let isConverting: Bool
    let compress: ([URL]) -> Void
    let convert: (URL, ShelfConversion) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 36, height: 36)
                .opacity(isConverting ? 0.35 : 1)
                .overlay {
                    if isConverting {
                        ProgressView().controlSize(.small).help("Dönüştürülüyor…")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isHovering, !isConverting {
                        // Önizleme: Quick Look.
                        Button { preview() } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.75)))
                        }
                        .buttonStyle(PressScaleStyle())
                        .offset(x: 8, y: -6)
                        .help("Önizle")
                        .notchTransition(.fade)
                    }
                }
            // Tek satır, ortadan kısaltılır (uzantı görünür); tam ad üzerine gelince.
            Text(verbatim: item.name)
                .font(NotchDesign.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: NotchDesign.Radius.medium, style: .continuous)
            .fill(isHovering ? NotchDesign.cardHoverFill : .clear))
        .onHover { isHovering = $0 }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .contentShape(Rectangle())
        // Çift tıklama: varsayılan uygulamada aç.
        .onTapGesture(count: 2) { if let url { NSWorkspace.shared.open(url) } }
        .onDrag {
            NSItemProvider(object: (url ?? item.url) as NSURL)
        }
        .contextMenu {
            Button("Aç") { if let url { NSWorkspace.shared.open(url) } }
            Button("Önizle") { preview() }
            Divider()
            if let url {
                ShareLink("Paylaş…", item: url)
            }
            Button("AirDrop ile gönder") { if let url { ShelfStore.shareViaAirDrop([url]) } }
            Button("Sıkıştır") { if let url { compress([url]) } }
            if let url, !ShelfConversion.options(for: url).isEmpty {
                Menu("Dönüştür") {
                    ForEach(ShelfConversion.options(for: url), id: \.self) { conversion in
                        Button(conversion.title) { convert(url, conversion) }
                    }
                }
                .disabled(isConverting)
            }
            Button("Yolu kopyala") { if let url { ShelfStore.copyPaths([url]) } }
            Button("Finder'da göster") { if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
            Divider()
            Button("Raftan kaldır") { shelf.remove(item.id) }
        }
        .help(item.url.path)
    }

    private var url: URL? { shelf.resolvedURL(for: item) }

    private func preview() {
        if let url { ShelfStore.quickLook([url]) }
    }
}
