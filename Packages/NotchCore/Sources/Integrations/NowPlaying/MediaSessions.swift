import Foundation

/// Bir oynatıcının oturumu. İki medya açıkken (ör. Chrome'da video, Spotify'da şarkı) her biri ayrı;
/// adaptör yalnız sistemin seçtiğini verdiği için diğeri çoklu oturum yardımcısından gelir.
public struct MediaSession: Identifiable, Equatable, Sendable {
    /// Süreç kimliği varsa "pid:<n>", yoksa bundle kimliği.
    public let id: String
    public var displayName: String?
    /// Simge ve ad için: tarayıcı içi oynatıcılarda üst uygulama.
    public var appBundleIdentifier: String?
    public var info: NowPlayingInfo
    /// Oynatıcının etkin komutları (MRMediaRemoteCommand); bilinmiyorsa nil (hepsi varsayılır).
    public var supportedCommands: Set<Int>?

    public init(id: String, displayName: String? = nil, appBundleIdentifier: String? = nil, info: NowPlayingInfo,
                supportedCommands: Set<Int>? = nil) {
        self.id = id
        self.displayName = displayName
        self.appBundleIdentifier = appBundleIdentifier
        self.info = info
        self.supportedCommands = supportedCommands
    }

    /// Örn. Chrome'daki tek video sonraki/önceki desteklemez; düğme soluk gösterilir.
    public func supports(_ command: MediaRemoteAdapterBundle.Command) -> Bool {
        supportedCommands?.contains(command.rawValue) ?? true
    }

    /// Yalnız adaptör akışından bilinen oturum (yardımcı yoksa ya da henüz bildirmediyse).
    init(systemInfo: NowPlayingInfo) {
        self.init(id: Self.identifier(for: systemInfo), appBundleIdentifier: systemInfo.bundleIdentifier,
                  info: systemInfo)
    }

    static func identifier(for info: NowPlayingInfo) -> String {
        info.processIdentifier.map { "pid:\($0)" } ?? "bundle:\(info.bundleIdentifier ?? "")"
    }

    /// Adaptörün bildirdiği oynatıcı bu oturum mu: süreç kimliği, yoksa bundle kimliği.
    func matches(_ other: NowPlayingInfo) -> Bool {
        if let pid = other.processIdentifier, let own = info.processIdentifier { return pid == own }
        return other.bundleIdentifier != nil && other.bundleIdentifier == info.bundleIdentifier
    }

    /// Gösterilecek oturum: elle seçilen (hâlâ varsa) → çalanlardan sistemin seçtiği → en son çalmaya
    /// başlayan → sistemin seçtiği (duraklatılmış) → ilk. Böylece sistem duraklatılmış bir videoyu
    /// seçmişken çalan şarkı gizlenmez.
    static func focus(in sessions: [MediaSession], selected: String?, system: String?,
                      playStartedAt: [String: Date]) -> MediaSession? {
        if let selected, let match = sessions.first(where: { $0.id == selected }) { return match }
        let playing = sessions.filter(\.info.isPlaying)
        if let system, let match = playing.first(where: { $0.id == system }) { return match }
        if let latest = playing.max(by: {
            (playStartedAt[$0.id] ?? .distantPast) < (playStartedAt[$1.id] ?? .distantPast)
        }) { return latest }
        if let system, let match = sessions.first(where: { $0.id == system }) { return match }
        return sessions.first
    }
}

/// Uygulama paketindeki çoklu oturum yardımcısı (Helpers/MediaSessions, kendi kodumuz). Adaptör gibi
/// `/usr/bin/perl` yükler. Bulunamazsa ya da çalışmazsa tek oturuma (adaptör) düşülür.
struct MediaSessionsBundle: Equatable, Sendable {
    let script: URL
    let library: URL

    static func locate(in bundle: Bundle = .main) -> MediaSessionsBundle? {
        guard let script = bundle.url(forResource: "media-sessions", withExtension: "pl"),
              let library = bundle.privateFrameworksURL?.appendingPathComponent("MediaSessions.dylib"),
              FileManager.default.fileExists(atPath: library.path) else { return nil }
        return MediaSessionsBundle(script: script, library: library)
    }

    func arguments(_ command: [String]) -> [String] {
        [script.path, library.path] + command
    }

    /// Komut sistemin seçtiği oynatıcıya değil, bu süreçteki oynatıcıya gider.
    func send(_ command: MediaRemoteAdapterBundle.Command, to pid: Int32) {
        perform(["send", String(pid), String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval, pid: Int32) {
        perform(["seek", String(pid), String(Int64(max(0, seconds) * 1_000_000))])
    }

    /// Ayrı süreçte; başarısızlıkta yardımcının hata metni de günlüğe düşer.
    private func perform(_ command: [String]) {
        let process = Process()
        process.executableURL = MediaRemoteAdapterBundle.perl
        process.arguments = arguments(command)
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let name = command.joined(separator: " ")
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Log.integrations.error("Oturum komutu başarısız (\(name, privacy: .public)): \(finished.terminationStatus) \(message, privacy: .private)")
        }
        do {
            try process.run()
        } catch {
            Log.integrations.error("Oturum komutu başlatılamadı: \(error.localizedDescription, privacy: .public)")
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Yardımcının `stream` çıktısını çözer: her satır `{"type":"sessions","sessions":[…]}`, tüm liste.
/// Kapak yalnız değişince gelir (`artworkData` yok = aynı, `null` = kalktı); burada saklanır.
public struct MediaSessionsParser {
    private var artwork: [Int32: Data] = [:]
    private var lastEmitted: [MediaSession]?

    public init() {}

    /// Çözülemeyen ya da öncekiyle aynı listeyi veren satır için nil döner.
    public mutating func consume(line: String) -> [MediaSession]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "sessions",
              let entries = object["sessions"] as? [[String: Any]] else {
            Log.integrations.error("Oturum satırı çözülemedi (\(line.utf8.count) bayt)")
            return nil
        }

        var sessions: [MediaSession] = []
        var seen = Set<Int32>()
        for var entry in entries {
            guard let pid = (entry["processIdentifier"] as? NSNumber)?.int32Value else { continue }
            seen.insert(pid)
            if let encoded = entry.removeValue(forKey: "artworkData") {
                artwork[pid] = (encoded as? String).flatMap { Data(base64Encoded: $0) }
            }
            guard case var .playing(info) = AdapterStreamParser.makeUpdate(from: entry) else { continue }
            info.artworkData = artwork[pid]
            sessions.append(MediaSession(
                id: "pid:\(pid)",
                displayName: entry["displayName"] as? String,
                appBundleIdentifier: (entry["parentApplicationBundleIdentifier"] as? String) ?? info.bundleIdentifier,
                info: info,
                supportedCommands: (entry["commands"] as? [NSNumber]).map { Set($0.map(\.intValue)) }))
        }
        artwork = artwork.filter { seen.contains($0.key) }
        guard sessions != lastEmitted else { return nil }
        lastEmitted = sessions
        return sessions
    }
}

/// Uzun yaşayan yardımcı süreci. Satırları arka planda çözer, yalnız değişen listeyi iletir.
final class MediaSessionsStream: @unchecked Sendable {
    private let process = Process()
    private var reader: PipeLineReader?
    private let lock = NSLock()
    private var stoppedByUs = false

    init(bundle: MediaSessionsBundle) {
        process.executableURL = MediaRemoteAdapterBundle.perl
        process.arguments = bundle.arguments(["stream"])
    }

    func start(onUpdate: @escaping @Sendable ([MediaSession]) -> Void,
               onExit: @escaping @Sendable (_ status: Int32, _ stoppedByUs: Bool) -> Void) throws {
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            onExit(process.terminationStatus, self?.wasStoppedByUs ?? true)
        }
        try process.run()
        var parser = MediaSessionsParser()
        reader = PipeLineReader(handle: output.fileHandleForReading) { line in
            if let sessions = parser.consume(line: line) { onUpdate(sessions) }
        }
        reader?.start()
    }

    func stop() {
        lock.withLock { stoppedByUs = true }
        if process.isRunning { process.terminate() }
    }

    private var wasStoppedByUs: Bool { lock.withLock { stoppedByUs } }
}
