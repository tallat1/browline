import Foundation
import Observation

/// GitHub Actions çalışmaları: seçilen depolarda son çalışmalar, sürenler ve bitenler. Kimlik için
/// kullanıcının kendi `gh` aracı çalıştırılır; uygulama anahtar görmez, saklamaz. İzin istemez.
/// Süren çalışma varken 30 sn'de bir, yoksa 3 dk'da bir sorulur.
@MainActor
@Observable
public final class CIMonitor {
    public struct Run: Identifiable, Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case active
            case success
            case failure
            /// İptal, atlandı, nötr…
            case other
        }

        public let id: Int
        public let repository: String
        public let workflow: String
        public let title: String
        public let branch: String
        public let state: State
        public let createdAt: Date
        public let url: URL?

        public init(id: Int, repository: String, workflow: String, title: String, branch: String, state: State,
                    createdAt: Date, url: URL?) {
            self.id = id
            self.repository = repository
            self.workflow = workflow
            self.title = title
            self.branch = branch
            self.state = state
            self.createdAt = createdAt
            self.url = url
        }

        /// "owner/repo" → "repo".
        public var repositoryName: String { repository.split(separator: "/").last.map(String.init) ?? repository }
    }

    public enum Status: Equatable, Sendable {
        case idle
        case running
        /// `gh` bulunamadı (Homebrew yolları denenir).
        case missingTool
        /// `gh auth login` yapılmamış ya da depo erişilemiyor.
        case failed(String)
    }

    public private(set) var runs: [Run] = []
    public private(set) var status: Status = .idle
    @ObservationIgnored public var onRunFinished: ((Run) -> Void)?
    @ObservationIgnored public var onActiveChanged: (([Run]) -> Void)?

    @ObservationIgnored private var repositories: [String] = []
    @ObservationIgnored private var onlyMine = true
    @ObservationIgnored private var login: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var hasLoaded = false

    static let activeInterval: Duration = .seconds(30)
    static let idleInterval: Duration = .seconds(180)
    nonisolated static let runsPerRepository = 5
    static let maximumRuns = 12

    public init() {}

    public var activeRuns: [Run] { runs.filter { $0.state == .active } }

    public func start(repositories: [String], onlyMine: Bool) {
        let cleaned = repositories.compactMap(Self.normalize)
        guard cleaned != self.repositories || onlyMine != self.onlyMine || task == nil else { return }
        stop()
        self.repositories = cleaned
        self.onlyMine = onlyMine
        guard !cleaned.isEmpty else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.poll()
                try? await Task.sleep(for: delay)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        runs = []
        status = .idle
        hasLoaded = false
        onActiveChanged?([])
    }

    /// Ayarlardan elle yenileme.
    public func refreshNow() {
        let repositories = self.repositories
        let onlyMine = self.onlyMine
        self.repositories = []
        start(repositories: repositories, onlyMine: onlyMine)
    }

    /// "https://github.com/a/b(.git)", "git@github.com:a/b.git", "a/b" → "a/b".
    public nonisolated static func normalize(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "git@github.com:", "ssh://git@github.com/", "github.com/"]
            where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        if value.hasSuffix("/") { value = String(value.dropLast()) }
        let parts = value.split(separator: "/")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return nil }
        return parts.joined(separator: "/")
    }

    private func poll() async -> Duration {
        guard let tool = Self.toolPath() else {
            status = .missingTool
            return Self.idleInterval
        }
        if onlyMine, login == nil {
            login = await Task.detached { Self.currentLogin(tool: tool) }.value
        }
        let repositories = self.repositories
        let user = onlyMine ? login : nil
        let results = await Task.detached(priority: .utility) {
            repositories.map { Self.fetch(tool: tool, repository: $0, user: user) }
        }.value
        var fresh: [Run] = []
        var failure: String?
        for result in results {
            switch result {
            case let .success(runs): fresh += runs
            case let .failure(error): failure = error.message
            }
        }
        apply(Array(fresh.sorted { $0.createdAt > $1.createdAt }.prefix(Self.maximumRuns)))
        status = failure.map(Status.failed) ?? .running
        return activeRuns.isEmpty ? Self.idleInterval : Self.activeInterval
    }

    /// Debug önizlemesi: gerçek okuma gibi uygulanır (bitenler bildirilir).
    public func preview(_ runs: [Run]) {
        hasLoaded = true
        apply(runs)
    }

    /// Bitenleri bildirir; ilk okumada geçmiş çalışmalar "bitti" sayılmaz.
    func apply(_ fresh: [Run]) {
        let previous = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        if hasLoaded {
            for run in fresh where run.state != .active && previous[run.id]?.state == .active {
                onRunFinished?(run)
            }
        }
        let wasActive = activeRuns.map(\.id)
        if fresh != runs { runs = fresh }
        if activeRuns.map(\.id) != wasActive { onActiveChanged?(activeRuns) }
        hasLoaded = true
    }

    // MARK: - gh

    nonisolated static func toolPath() -> String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated static func currentLogin(tool: String) -> String? {
        guard let output = run(tool, ["api", "user", "--jq", ".login"]), output.status == 0 else { return nil }
        let login = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : login
    }

    nonisolated static func fetch(tool: String, repository: String, user: String?) -> Result<[Run], FetchError> {
        var arguments = ["run", "list", "-R", repository, "-L", String(runsPerRepository), "--json",
                         "databaseId,workflowName,displayTitle,headBranch,status,conclusion,createdAt,url"]
        if let user { arguments += ["-u", user] }
        guard let output = run(tool, arguments) else { return .failure(FetchError("gh çalıştırılamadı")) }
        guard output.status == 0 else {
            Log.integrations.error("CI: \(repository, privacy: .private) okunamadı (gh çıkış \(output.status))")
            return .failure(FetchError(repository))
        }
        return .success(parse(output.data, repository: repository))
    }

    public struct FetchError: Error, Equatable, Sendable {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// `gh run list --json …` dizisi.
    nonisolated static func parse(_ data: Data, repository: String) -> [Run] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let formatter = ISO8601DateFormatter()
        return items.compactMap { item in
            guard let id = (item["databaseId"] as? NSNumber)?.intValue else { return nil }
            let status = (item["status"] as? String ?? "").lowercased()
            let conclusion = (item["conclusion"] as? String ?? "").lowercased()
            let state: Run.State = if status != "completed" {
                .active
            } else if conclusion == "success" {
                .success
            } else if ["failure", "timed_out", "startup_failure", "action_required"].contains(conclusion) {
                .failure
            } else {
                .other
            }
            return Run(id: id, repository: repository,
                       workflow: item["workflowName"] as? String ?? "",
                       title: item["displayTitle"] as? String ?? "",
                       branch: item["headBranch"] as? String ?? "",
                       state: state,
                       createdAt: (item["createdAt"] as? String).flatMap(formatter.date(from:)) ?? .distantPast,
                       url: (item["url"] as? String).flatMap(URL.init(string:)))
        }
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, data: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        // GUI uygulamasında PATH kısa; gh git'i ve yapılandırmasını bulabilsin.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, data)
    }

    // MARK: - Öneriler

    /// Klasördeki git depolarından GitHub'a bağlı ve son 14 günde commit alanlar, en yeni önce.
    /// Yalnız ayarlardaki düğmeyle, arka planda çalışır.
    public nonisolated static func suggestedRepositories(in root: URL, limit: Int = 6, now: Date = .now) -> [String] {
        var candidates: [(String, Date)] = []
        for directory in gitDirectories(in: root, depth: 3) {
            guard let config = try? String(contentsOf: directory.appendingPathComponent(".git/config"), encoding: .utf8),
                  let remote = originURL(in: config), let repository = normalize(remote) else { continue }
            let head = directory.appendingPathComponent(".git/logs/HEAD")
            guard let modified = (try? FileManager.default.attributesOfItem(atPath: head.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) < 14 * 86_400 else { continue }
            candidates.append((repository, modified))
        }
        var seen = Set<String>()
        return candidates.sorted { $0.1 > $1.1 }.map(\.0).filter { seen.insert($0.lowercased()).inserted }.prefix(limit).map { $0 }
    }

    nonisolated static func originURL(in config: String) -> String? {
        var inOrigin = false
        for line in config.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inOrigin = trimmed == "[remote \"origin\"]"; continue }
            if inOrigin, trimmed.hasPrefix("url"), let equals = trimmed.firstIndex(of: "=") {
                let url = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                return url.contains("github.com") ? url : nil
            }
        }
        return nil
    }

    nonisolated private static func gitDirectories(in root: URL, depth: Int) -> [URL] {
        let fileManager = FileManager.default
        guard depth >= 0, let children = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if fileManager.fileExists(atPath: child.appendingPathComponent(".git/config").path) {
                result.append(child)
            } else if depth > 0, !["node_modules", "build", "DerivedData"].contains(child.lastPathComponent) {
                result += gitDirectories(in: child, depth: depth - 1)
            }
        }
        return result
    }
}
