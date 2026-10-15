import Foundation
import Observation

/// Claude planı limitleri (5 saatlik oturum, haftalık). Tek belgelenmiş kaynak Claude Code durum
/// satırı JSON'undaki `rate_limits`: durum satırı betiği değerleri uygulama klasörüne yazar, burası
/// klasörü olay güdümlü izler (yoklama yok). Veri yalnız bir Claude Code oturumu çalışırken tazelenir;
/// bu yüzden yakalanma zamanı da tutulur.
@MainActor
@Observable
public final class ClaudeUsageMonitor {
    public struct Window: Equatable, Sendable {
        /// 0–100
        public var usedPercentage: Double
        public var resetsAt: Date?
    }

    public struct Usage: Equatable, Sendable {
        public var fiveHour: Window?
        public var sevenDay: Window?
        public var capturedAt: Date
    }

    public private(set) var usage: Usage?
    /// Durum satırı betiğinin en son çalıştığı an (limit gelmese de). nil: hiç çalışmadı, kurulu değil.
    public private(set) var statuslineSeenAt: Date?
    /// Claude Code'un etkin hesabı (`~/.claude.json`); sekme her göründüğünde yeniden okunur.
    public private(set) var account: ClaudeAccount?
    /// Oturum kayıtlarından: dolmuş ve henüz sıfırlanmamış limitler (yüzde değil, yalnız "doldu").
    public private(set) var activeLimits: [ClaudeLimitHit] = []
    @ObservationIgnored private let limitLog = ClaudeLimitLog()
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    /// 5 saatlik pencere %80 ve %95 eşiğini yukarı geçince.
    @ObservationIgnored public var onAlert: ((Int) -> Void)?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?

    public nonisolated static let alertThresholds = [80, 95]

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.talatozcoban.notchmvp", isDirectory: true)
    }

    public init(directory: URL = ClaudeUsageMonitor.defaultDirectory) {
        fileURL = directory.appendingPathComponent("claude-usage.json")
        seenURL = directory.appendingPathComponent("claude-statusline.seen")
    }

    @ObservationIgnored private let seenURL: URL

    /// Sekme görünürken çağrılır: iz dosyasının yalnız zamanı değişir, klasör olayı gelmez.
    public func refreshSeen() {
        let loaded = ClaudeAccount.load()
        if loaded != account { account = loaded }
        refreshLimits()
        let seen = (try? seenURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if seen != statuslineSeenAt { statuslineSeenAt = seen }
    }

    public var isRunning: Bool { source != nil }

    public func start() {
        guard source == nil else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload(alerting: false)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        // Betik geçici dosyaya yazıp yeniden adlandırır; klasördeki her değişiklikte okunur.
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload(alerting: true) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        usage = nil
        limitTask?.cancel()
        limitTask = nil
        activeLimits = []
    }

    #if DEBUG
    /// Yalnız debug: "doldu" kartını gerçek limit beklemeden göstermek için ÖRNEK; dosyaya yazılmaz,
    /// uygulama yeniden açılınca ya da sekme yeniden taranınca kaybolur.
    public func previewLimit(_ hits: [ClaudeLimitHit]) { activeLimits = hits }
    #endif

    /// Kayıt taraması dosya okur; ana iş parçacığında değil. Üst üste çağrı tek taramaya iner.
    private func refreshLimits() {
        guard limitTask == nil else { return }
        let log = limitLog
        limitTask = Task { [weak self] in
            let hits = await Task.detached(priority: .utility) { log.activeHits() }.value
            guard let self, !Task.isCancelled else { return }
            self.limitTask = nil
            if hits != self.activeLimits {
                self.activeLimits = hits
                Log.integrations.notice("Claude kayıtları: \(hits.count) etkin limit")
            }
        }
    }

    private func reload(alerting: Bool) {
        refreshSeen()
        guard let data = try? Data(contentsOf: fileURL),
              let new = Self.parse(data, fallbackCapturedAt: (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .now),
              new != usage else { return }
        let old = usage
        usage = new
        Log.integrations.notice("Claude limitleri: oturum \(new.fiveHour.map { Int($0.usedPercentage) } ?? -1), hafta \(new.sevenDay.map { Int($0.usedPercentage) } ?? -1)")
        if alerting, let percent = new.fiveHour?.usedPercentage,
           let threshold = Self.crossedThreshold(from: old?.fiveHour?.usedPercentage, to: percent) {
            onAlert?(threshold)
        }
    }

    /// Betiğin kısa biçimi (`five_hour`, `seven_day`, `captured_at`) ya da durum satırı JSON'unun
    /// kendisi (`rate_limits` altında) kabul edilir. İki pencere de yoksa nil.
    nonisolated static func parse(_ data: Data, fallbackCapturedAt: Date) -> Usage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let limits = root["rate_limits"] as? [String: Any] ?? root
        func window(_ key: String) -> Window? {
            guard let value = limits[key] as? [String: Any],
                  let used = (value["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (value["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return Window(usedPercentage: min(max(used, 0), 100), resetsAt: reset)
        }
        let fiveHour = window("five_hour"), sevenDay = window("seven_day")
        guard fiveHour != nil || sevenDay != nil else { return nil }
        let captured = (root["captured_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return Usage(fiveHour: fiveHour, sevenDay: sevenDay, capturedAt: captured ?? fallbackCapturedAt)
    }

    /// Yalnız yukarı doğru geçişte; ilk okuma (önceki yok) uyarı üretmez.
    nonisolated static func crossedThreshold(from old: Double?, to new: Double) -> Int? {
        guard let old else { return nil }
        return alertThresholds.last { old < Double($0) && new >= Double($0) }
    }
}
