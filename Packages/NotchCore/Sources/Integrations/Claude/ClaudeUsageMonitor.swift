import Foundation
import Observation

/// Claude planı limitleri (5 saatlik oturum, haftalık). İki kaynak, hangisi daha yeniyse o gösterilir:
/// - Claude Code'a `/usage` sormak (`ClaudeUsageProbe`): masaüstü uygulamasında da çalışır. Claude oturumu
///   çalışırken 5 dakikada, boşta 30 dakikada bir; ayrıca tur bitince ve sayfa açılınca (en sık 2 dakikada bir).
/// - Terminaldeki durum satırı betiği: `rate_limits` değerlerini uygulama klasörüne yazar, klasör olay
///   güdümlü izlenir.
@MainActor
@Observable
public final class ClaudeUsageMonitor {
    public struct Window: Equatable, Sendable {
        /// 0–100
        public var usedPercentage: Double
        public var resetsAt: Date?

        public init(usedPercentage: Double, resetsAt: Date?) {
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }
    }

    public enum Source: Equatable, Sendable {
        /// Terminaldeki durum satırı betiği; yalnız oturum çalışırken tazelenir.
        case statusline
        /// Claude Code'a `/usage` sorularak.
        case claudeCode
    }

    public struct Usage: Equatable, Sendable {
        public var fiveHour: Window?
        public var sevenDay: Window?
        public var capturedAt: Date
        public var source: Source

        public init(fiveHour: Window?, sevenDay: Window?, capturedAt: Date, source: Source = .statusline) {
            self.fiveHour = fiveHour
            self.sevenDay = sevenDay
            self.capturedAt = capturedAt
            self.source = source
        }
    }

    public enum ProbeState: Equatable, Sendable {
        case idle
        case running
        case succeeded
        case failed(ClaudeUsageProbe.Failure)
    }

    public private(set) var usage: Usage?
    /// Son `/usage` yoklamasının durumu; veri yokken sayfa nedenini buradan söyler.
    public private(set) var probeState: ProbeState = .idle

    /// Hook etkinliklerinden: bir Claude oturumu çalışıyor ya da onay bekliyor. Yoklama sıklaşır; tur bitince
    /// (etkin → boşta) bir kez hemen sorulur.
    public var isClaudeActive = false {
        didSet {
            guard isClaudeActive != oldValue, isRunning else { return }
            schedule(refreshNow: !isClaudeActive)
        }
    }

    /// Claude Code'un etkin hesabı (`~/.claude.json`); sekme her göründüğünde yeniden okunur.
    public private(set) var account: ClaudeAccount?
    /// Oturum kayıtlarından: dolmuş ve henüz sıfırlanmamış limitler (yüzde değil, yalnız "doldu").
    public private(set) var activeLimits: [ClaudeLimitHit] = []
    @ObservationIgnored private let limitLog = ClaudeLimitLog()
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    /// 5 saatlik pencere %80 ve %95 eşiğini yukarı geçince.
    @ObservationIgnored public var onAlert: ((Int) -> Void)?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let probeDirectory: URL
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var lastProbeAt: Date?

    public nonisolated static let alertThresholds = [80, 95]
    nonisolated static let activeInterval: Duration = .seconds(5 * 60)
    nonisolated static let idleInterval: Duration = .seconds(30 * 60)
    /// Tur sonu ve sayfa açılışı bundan sık sormaz; Claude Code'un limit ucu sık istekte kısıtlıyor.
    nonisolated static let minimumInterval: TimeInterval = 2 * 60

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.talatozcoban.browline", isDirectory: true)
    }

    public init(directory: URL = ClaudeUsageMonitor.defaultDirectory) {
        fileURL = directory.appendingPathComponent("claude-usage.json")
        probeDirectory = directory.appendingPathComponent("claude-usage-probe", isDirectory: true)
    }

    /// Sekme görünürken çağrılır: hesap değişmiş, oturum kayıtlarına yeni limit düşmüş olabilir.
    public func refreshAccountAndLimits() {
        let loaded = ClaudeAccount.load()
        if loaded != account { account = loaded }
        refreshLimits()
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
        schedule(refreshNow: true)
    }

    public func stop() {
        source?.cancel()
        source = nil
        usage = nil
        limitTask?.cancel()
        limitTask = nil
        activeLimits = []
        scheduleTask?.cancel()
        scheduleTask = nil
        probeTask?.cancel()
        probeTask = nil
        lastProbeAt = nil
        probeState = .idle
    }

    /// Claude Code'a `/usage` sorar; en sık `minimumInterval`'da bir. Sonuç arka planda gelir.
    public func refreshFromClaudeCode() {
        guard isRunning, probeTask == nil else { return }
        if let lastProbeAt, Date.now.timeIntervalSince(lastProbeAt) < Self.minimumInterval { return }
        lastProbeAt = .now
        probeState = .running
        let directory = probeDirectory
        probeTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { ClaudeUsageProbe.fetch(workingDirectory: directory) }.value
            guard let self, !Task.isCancelled else { return }
            probeTask = nil
            switch result {
            case .success(let new):
                probeState = .succeeded
                apply(new, alerting: true)
            case .failure(let failure):
                probeState = .failed(failure)
                Log.integrations.notice("Claude /usage okunamadı: \(String(describing: failure), privacy: .public)")
            }
        }
    }

    /// Yoklama döngüsünü sıklığa göre yeniden kurar.
    private func schedule(refreshNow: Bool) {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            var first = true
            while !Task.isCancelled {
                let interval: Duration
                do {
                    guard let self else { return }
                    if !first || refreshNow { refreshFromClaudeCode() }
                    interval = isClaudeActive ? Self.activeInterval : Self.idleInterval
                }
                first = false
                try? await Task.sleep(for: interval)
            }
        }
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
        refreshAccountAndLimits()
        guard let data = try? Data(contentsOf: fileURL),
              let new = Self.parse(data, fallbackCapturedAt: (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .now),
              new != usage else { return }
        apply(new, alerting: alerting)
    }

    private func apply(_ new: Usage, alerting: Bool) {
        let old = usage
        // İki kaynak var: eski bir durum satırı dosyası yeni `/usage` sonucunu ezmesin.
        guard Self.shouldReplace(old, with: new) else { return }
        usage = new
        Log.integrations.notice("Claude limitleri (\(String(describing: new.source), privacy: .public)): oturum \(new.fiveHour.map { Int($0.usedPercentage) } ?? -1), hafta \(new.sevenDay.map { Int($0.usedPercentage) } ?? -1)")
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

    nonisolated static func shouldReplace(_ current: Usage?, with new: Usage) -> Bool {
        guard let current else { return true }
        return new != current && new.capturedAt >= current.capturedAt
    }

    /// Yalnız yukarı doğru geçişte; ilk okuma (önceki yok) uyarı üretmez.
    nonisolated static func crossedThreshold(from old: Double?, to new: Double) -> Int? {
        guard let old else { return nil }
        return alertThresholds.last { old < Double($0) && new >= Double($0) }
    }
}
