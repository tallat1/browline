import AppKit
import Observation

/// Notch'a bırakılan dosyalar. Kopya değil, bookmark ile özgün dosyaya başvuru tutulur;
/// dosya taşınırsa bookmark izler, silinirse öğe kendiliğinden düşer. Yeniden başlatmada korunur.
@MainActor
@Observable
public final class ShelfStore {
    public struct Item: Identifiable, Codable, Equatable, Sendable {
        public let id: UUID
        public var url: URL
        public var bookmark: Data?
        public let addedAt: Date

        public var name: String { url.lastPathComponent }
    }

    public private(set) var items: [Item] = []
    public static let maximumItems = 30

    @ObservationIgnored private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.talatozcoban.notchmvp", isDirectory: true)
        fileURL = base.appendingPathComponent("shelf.json")
        load()
    }

    public func add(_ urls: [URL]) {
        // Hem raftakilerle hem aynı bırakmanın kendi içinde yinelenenleri ele.
        var seen = Set(items.map(\.url.standardizedFileURL))
        let new = urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL).inserted }.map {
            Item(id: UUID(), url: $0, bookmark: try? $0.bookmarkData(), addedAt: .now)
        }
        guard !new.isEmpty else { return }
        items = Array((new.reversed() + items).prefix(Self.maximumItems))
        // Dosya adı kişisel; yalnız sayı.
        Log.integrations.notice("Raf: \(new.count) öğe eklendi, toplam \(self.items.count)")
        save()
    }

    public func remove(_ id: Item.ID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        items.removeAll()
        save()
    }

    /// Bookmark'ı çözer; dosya taşındıysa yolu günceller, yoksa öğeyi kaldırıp nil döner.
    public func resolvedURL(for item: Item) -> URL? {
        var url = item.url
        if let bookmark = item.bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) {
                url = resolved
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            remove(item.id)
            return nil
        }
        if url != item.url, let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].url = url
            items[index].bookmark = try? url.bookmarkData()
            save()
        }
        return url
    }

    public var resolvedURLs: [URL] { items.compactMap(resolvedURL(for:)) }

    /// AirDrop paylaşım sayfası; servis yoksa (AirDrop kapalı) false.
    @discardableResult
    public static func shareViaAirDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            Log.integrations.notice("AirDrop: servis kullanılamıyor (\(urls.count) öğe)")
            return false
        }
        service.perform(withItems: urls)
        Log.integrations.notice("AirDrop: paylaşım açıldı (\(urls.count) öğe)")
        return true
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
        } catch {
            Log.integrations.error("Raf kaydedilemedi: \(error.localizedDescription, privacy: .public)")
        }
    }
}
