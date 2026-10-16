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
        // Hem raftakilerle hem aynı bırakmanın kendi içinde yinelenenleri ele. Aynı dosya farklı
        // biçimde gelebiliyor: raftan sürüklenen öğe bookmark'tan çözülmüş yolla (/private/tmp)
        // geri bırakılıyor, Finder dosya başvurusu URL'si (file:///.file/id=…) verebiliyor.
        var seen = Set(items.map { Self.identity(of: $0.url) })
        let new = urls.filter { $0.isFileURL && seen.insert(Self.identity(of: $0)).inserted }.map {
            Item(id: UUID(), url: $0, bookmark: try? $0.bookmarkData(), addedAt: .now)
        }
        guard !new.isEmpty else { return }
        items = Array((new.reversed() + items).prefix(Self.maximumItems))
        // Dosya adı kişisel; yalnız sayı.
        Log.integrations.notice("Raf: \(new.count) öğe eklendi, toplam \(self.items.count)")
        save()
    }

    /// Karşılaştırma anahtarı: dosya başvurusu yola, sembolik bağlar gerçek yola çevrilir.
    public nonisolated static func identity(of url: URL) -> String {
        let path = (url as NSURL).filePathURL ?? url
        return path.resolvingSymlinksInPath().standardizedFileURL.path
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

    // MARK: - Raf eylemleri (DynamicLake DynaClip'teki derinlik)

    /// Zip arşivi: tek öğe kendi klasörüne ("ad.zip"), birden çoğu İndirilenler'e ("Arşiv … .zip"); klasör
    /// yazılamıyorsa İndirilenler. `ditto` macOS'un Finder "Sıkıştır" ile aynı biçimini üretir. Ayrı
    /// süreçte; bitince sonuç (ya da nil) ana iş parçacığında döner.
    public static func compress(_ urls: [URL], downloads: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
                                now: Date = .now, completion: @escaping @MainActor (URL?) -> Void) {
        guard !urls.isEmpty else { completion(nil); return }
        let destination = archiveURL(for: urls, downloads: downloads, now: now)
        Task.detached(priority: .userInitiated) {
            let result = runCompression(urls, to: destination)
            await MainActor.run { completion(result) }
        }
    }

    /// Dosya sözüyle gelenlerin (ekran görüntüsü küçük resmi, Fotoğraflar) yazıldığı yer: macOS'un ekran
    /// görüntülerini kaydettiği klasör (`com.apple.screencapture location`), yoksa Masaüstü. Küçük resim
    /// rafa sürüklenince macOS dosyayı kendi yerine yazmaz; böylece yine aynı yerde durur.
    public nonisolated static func promiseDestination() -> URL {
        let fileManager = FileManager.default
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue { return url }
        }
        return fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Ad çakışırsa "ad 2.uzantı", "ad 3.uzantı"…
    nonisolated static func unique(_ base: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = base
        var counter = 2
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            candidate = base.deletingLastPathComponent().appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }

    /// Kaynağın yanı, yazılamıyorsa İndirilenler.
    nonisolated static func outputDirectory(for source: URL, downloads: URL) -> URL {
        let parent = source.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path) ? parent : downloads
    }

    nonisolated static func archiveURL(for urls: [URL], downloads: URL, now: Date) -> URL {
        if urls.count == 1 {
            let directory = outputDirectory(for: urls[0], downloads: downloads)
            return unique(directory.appendingPathComponent(urls[0].lastPathComponent + ".zip"))
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return unique(downloads.appendingPathComponent("Arşiv \(formatter.string(from: now)).zip"))
    }

    /// Birden çok öğe geçici klasörde toplanır (kopyalar değil, ditto'nun ağaç kopyası), sonra paketlenir.
    nonisolated static func runCompression(_ urls: [URL], to destination: URL) -> URL? {
        let fileManager = FileManager.default
        var source = urls[0]
        var staging: URL?
        if urls.count > 1 {
            let folder = fileManager.temporaryDirectory.appendingPathComponent("notch-arsiv-\(UUID().uuidString)")
                .appendingPathComponent(destination.deletingPathExtension().lastPathComponent)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                for url in urls where run("/usr/bin/ditto", [url.path, folder.appendingPathComponent(url.lastPathComponent).path]) != 0 {
                    return nil
                }
            } catch {
                return nil
            }
            source = folder
            staging = folder.deletingLastPathComponent()
        }
        defer { if let staging { try? fileManager.removeItem(at: staging) } }
        let status = run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path])
        guard status == 0 else {
            Log.integrations.error("Sıkıştırma başarısız: \(status)")
            return nil
        }
        Log.integrations.notice("Raf: \(urls.count) öğe sıkıştırıldı")
        return destination
    }

    nonisolated static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Quick Look önizlemesi. Odak almayan panelde QLPreviewPanel yanıtlayıcı zinciri olmadan açılmıyor;
    /// macOS'un kendi Quick Look aracı aynı pencereyi açar.
    public static func quickLook(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p"] + urls.map(\.path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            Log.integrations.notice("Raf: Quick Look (\(urls.count) öğe)")
        } catch {
            Log.integrations.error("Quick Look açılamadı: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Yolu panoya: dosya olarak (Finder'a yapıştırılır) ve düz metin olarak (terminale yapıştırılır).
    public static func copyPaths(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        guard !urls.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
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
