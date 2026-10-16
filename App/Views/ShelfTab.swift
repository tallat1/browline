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
                Spacer(minLength: 0)
                // Eşit ağırlıkta metin düğmeleri: sayfanın asıl işi sürüklemek (2026-10-16 denetimi).
                HStack(spacing: NotchDesign.Space.xs) {
                    Text("\(shelf.items.count) öğe")
                        .font(NotchDesign.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Sistem paylaşım menüsü: AirDrop, Mesajlar, Mail, Notlar…
                    ShareLink(items: shelf.resolvedURLs) {
                        Label("Paylaş", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(QuietButtonStyle())
                    Button {
                        compress(shelf.resolvedURLs)
                    } label: {
                        Label(isCompressing ? "Sıkıştırılıyor…" : "Sıkıştır", systemImage: "doc.zipper")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isCompressing)
                    .help("Raftaki her şeyi tek zip'te toplar (İndirilenler)")
                    convertMenu
                    Button("Temizle") { shelf.clear() }
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// Raftaki tüm uygun dosyalara uygulanabilen dönüşümler; yanında kaç dosyaya uygulanacağı.
    private var convertMenu: some View {
        let pairs = shelf.items.compactMap { item in shelf.resolvedURL(for: item).map { (item, $0) } }
        var groups: [(ShelfConversion, [(ShelfStore.Item, URL)])] = []
        for pair in pairs {
            for option in ShelfConversion.options(for: pair.1) {
                if let index = groups.firstIndex(where: { $0.0 == option }) {
                    groups[index].1.append(pair)
                } else {
                    groups.append((option, [pair]))
                }
            }
        }
        return Menu {
            ForEach(groups, id: \.0) { option, targets in
                Button(targets.count > 1 ? "\(option.title) (\(targets.count))" : option.title) {
                    for (item, url) in targets { convert(item, url, option) }
                }
            }
        } label: {
            Label("Dönüştür…", systemImage: "arrow.triangle.2.circlepath")
                .font(NotchDesign.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Color.white.opacity(groups.isEmpty ? 0.3 : 0.6))
        .disabled(groups.isEmpty || !converting.isEmpty)
        .help(groups.isEmpty ? String(localized: "Raftaki dosyalar dönüştürülemiyor (görsel ya da video yok)")
                             : String(localized: "Görsel ve videoları dönüştürür; özgünler yerinde kalır"))
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
