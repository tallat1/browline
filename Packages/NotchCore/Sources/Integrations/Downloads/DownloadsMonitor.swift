import Foundation
import Observation

/// Tarayıcıların yarım indirme adları: Chrome/Edge/Brave/Arc `.crdownload`, Safari `.download`
/// paketi, Firefox `.part`. Tamamlanınca bu ek düşer ve dosya son adını alır.
public enum DownloadNaming {
    static let suffixes = [".crdownload", ".download", ".part"]

    /// Yarım indirme değilse nil; değilse dosyanın tamamlanınca alacağı ad.
    public static func finalName(forPartial name: String) -> String? {
        guard !name.hasPrefix(".") else { return nil }
        for suffix in suffixes where name.hasSuffix(suffix) && name.count > suffix.count {
            return String(name.dropLast(suffix.count))
        }
        return nil
    }
}

/// İndirilenler klasöründeki süren indirmeler. Klasör değişikliği olay güdümlü (DispatchSource);
/// boyut büyümesi klasör olayı üretmediği için yalnız indirme sürerken saniyede bir okunur.
/// ⚠️ İndirilenler klasörü TCC korumalı: ilk erişimde sistem izin ister; bu yüzden modül isteğe bağlı.
@MainActor
@Observable
public final class DownloadsMonitor {
    public struct Download: Identifiable, Equatable, Sendable {
        /// Yarım dosyanın adı.
        public let id: String
        /// Tamamlanınca alacağı ad.
        public let name: String
        public var bytes: Int64
        public var totalBytes: Int64?

        public var fraction: Double? {
            guard let totalBytes, totalBytes > 0 else { return nil }
            return min(1, Double(bytes) / Double(totalBytes))
        }
    }

    public private(set) var active: [Download] = []
    @ObservationIgnored public var onActiveChanged: (([Download]) -> Void)?
    @ObservationIgnored public var onFinished: ((_ name: String) -> Void)?

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    public var isRunning: Bool { source != nil }

    public func start() {
        guard source == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.integrations.error("İndirilenler klasörü açılamadı (izin?): \(self.directory.path, privacy: .public)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        scan()
    }

    public func stop() {
        source?.cancel()
        source = nil
        refreshTask?.cancel()
        refreshTask = nil
        if !active.isEmpty {
            active = []
            onActiveChanged?(active)
        }
    }

    func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var current: [Download] = []
        for name in names {
            guard let finalName = DownloadNaming.finalName(forPartial: name) else { continue }
            let url = directory.appendingPathComponent(name)
            let (bytes, total) = Self.progress(of: url)
            current.append(Download(id: name, name: finalName, bytes: bytes, totalBytes: total))
        }
        current.sort { $0.id < $1.id }

        // Yarım dosya kayboldu ve son adıyla bir dosya var: tamamlandı.
        let currentIDs = Set(current.map(\.id))
        for finished in active where !currentIDs.contains(finished.id) && names.contains(finished.name) {
            onFinished?(finished.name)
        }
        if current != active {
            active = current
            onActiveChanged?(current)
        }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard !active.isEmpty else { return }
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            self.scan()
        }
    }

    /// Safari paketinin Info.plist'i toplam boyutu taşır; diğerlerinde yalnız inen bayt bilinir.
    static func progress(of url: URL) -> (bytes: Int64, total: Int64?) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return (0, nil) }
        guard isDirectory.boolValue else {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            return (size ?? 0, nil)
        }
        if let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) {
            let soFar = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value
            let total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
            if let soFar { return (soFar, total.flatMap { $0 > 0 ? $0 : nil }) }
        }
        var bytes: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        while let item = enumerator?.nextObject() as? URL {
            bytes += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return (bytes, nil)
    }
}
