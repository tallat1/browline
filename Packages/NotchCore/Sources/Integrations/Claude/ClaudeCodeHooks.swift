import Foundation

/// Claude Code bağlantısı: Browline'ın kancalarını `~/.claude/settings.json`'a ekler, günceller ya da kaldırır.
/// Kancalar "Claude çalışıyor" etkinliğini, izin ve seçenekli soruları, karar kartını ve limit tazelemesini besler.
///
/// Dosyaya yalnız Browline'ın kendi kanca girdileri değişir: komutu `notch-hook.sh` ya da `…/Helpers/notch`
/// geçenler (eski elle kurulumlar dahil). Başka kancalar, anahtar sırası ve sayılar korunur (`OrderedJSON`);
/// yazmadan önce yanına tarihli yedek alınır, yazılan dosya yeniden okunup doğrulanır, bozuksa yedek geri konur.
/// `CLAUDE_CONFIG_DIR` ile başka klasör kullanan kurulum görülmez (GUI uygulaması kabuk ortamını bilmez).
public enum ClaudeCodeHooks {
    public enum Status: Equatable, Sendable {
        /// `~/.claude` yok: Claude Code hiç çalıştırılmamış.
        case claudeNotFound
        case notConnected
        case connected
        /// Browline kancaları var ama bu uygulamanınkiyle aynı değil (uygulama taşındı, eski elle kurulum).
        case needsUpdate
    }

    public struct Paths: Equatable, Sendable {
        public var cli: URL
        public var script: URL

        public init(cli: URL, script: URL) {
            self.cli = cli
            self.script = script
        }

        /// Uygulama paketindeki araç ve betik.
        public static func bundled(in bundle: Bundle = .main) -> Paths {
            Paths(cli: bundle.bundleURL.appendingPathComponent("Contents/Helpers/notch"),
                  script: bundle.bundleURL.appendingPathComponent("Contents/Resources/notch-hook.sh"))
        }
    }

    struct Entry: Equatable {
        var event: String
        var matcher: String?
        var command: String
        var timeout: Int
    }

    public enum Failure: Error, Equatable {
        case claudeNotFound
        case unreadable
        case writeFailed
    }

    public static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Kancaların ilk kez eklenmesi gereken olaylar; `Examples/claude-code/settings-hooks.json` ile aynı.
    static func entries(for paths: Paths) -> [Entry] {
        let hook = "NOTCH_CLI=\(shellQuoted(paths.cli.path)) /bin/bash \(shellQuoted(paths.script.path))"
        return [
            Entry(event: "UserPromptSubmit", matcher: nil, command: hook, timeout: 5),
            Entry(event: "PostToolUse", matcher: "*", command: hook, timeout: 5),
            Entry(event: "Notification", matcher: nil, command: hook, timeout: 5),
            Entry(event: "Stop", matcher: nil, command: hook, timeout: 5),
            Entry(event: "SessionEnd", matcher: nil, command: hook, timeout: 5),
            // Kanca, sorudan (110 sn) biraz uzun beklemeli; yanıt yoksa Claude kendi penceresini gösterir.
            Entry(event: "PermissionRequest", matcher: "*", command: "\(shellQuoted(paths.cli.path)) claude-permission --timeout 110",
                  timeout: 120),
        ]
    }

    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Browline'ın kancası mı: betik ya da paketteki `notch` aracı (elle kurulan eski biçimler dahil).
    static func isOwned(_ command: String) -> Bool {
        command.contains("notch-hook.sh") || command.contains("/Helpers/notch")
    }

    // MARK: - Durum

    public static func status(paths: Paths, settingsURL: URL = settingsURL) -> Status {
        guard FileManager.default.fileExists(atPath: settingsURL.deletingLastPathComponent().path) else { return .claudeNotFound }
        guard let data = try? Data(contentsOf: settingsURL), let root = try? OrderedJSON.parse(data) else { return .notConnected }
        return status(of: root, paths: paths)
    }

    static func status(of root: OrderedJSON, paths: Paths) -> Status {
        let owned = ownedEntries(in: root)
        if owned.isEmpty { return .notConnected }
        let desired = entries(for: paths)
        let matches = owned.count == desired.count && desired.allSatisfy { want in
            owned.contains { $0.event == want.event && $0.matcher == want.matcher && $0.command == want.command }
        }
        return matches ? .connected : .needsUpdate
    }

    static func ownedEntries(in root: OrderedJSON) -> [Entry] {
        guard case let .object(events)? = root["hooks"] else { return [] }
        return events.flatMap { event, groups -> [Entry] in
            (groups.arrayValue ?? []).flatMap { group -> [Entry] in
                (group["hooks"]?.arrayValue ?? []).compactMap { hook in
                    guard let command = hook["command"]?.stringValue, isOwned(command) else { return nil }
                    let timeout: Int = if case let .number(text)? = hook["timeout"] { Int(text) ?? 0 } else { 0 }
                    return Entry(event: event, matcher: group["matcher"]?.stringValue, command: command, timeout: timeout)
                }
            }
        }
    }

    // MARK: - Dönüşümler (dosyaya dokunmaz)

    /// Önce eski Browline girdileri temizlenir, sonra güncelleri olayların sonuna eklenir.
    static func connecting(_ root: OrderedJSON, paths: Paths) -> OrderedJSON {
        var hooks = disconnected(root)["hooks"] ?? .object([])
        for entry in entries(for: paths) {
            var group: [(String, OrderedJSON)] = []
            if let matcher = entry.matcher { group.append(("matcher", .string(matcher))) }
            group.append(("hooks", .array([.object([("type", .string("command")), ("command", .string(entry.command)),
                                                     ("timeout", .number(String(entry.timeout)))])])))
            let existing = hooks[entry.event]?.arrayValue ?? []
            hooks = hooks.setting(entry.event, to: .array(existing + [.object(group)]))
        }
        return disconnected(root).setting("hooks", to: hooks)
    }

    /// Yalnız Browline girdileri kalkar; boşalan grup, olay ve `hooks` da kalkar.
    static func disconnected(_ root: OrderedJSON) -> OrderedJSON {
        guard case let .object(events)? = root["hooks"] else { return root }
        var kept: [(String, OrderedJSON)] = []
        for (event, groupsValue) in events {
            guard let groups = groupsValue.arrayValue else { kept.append((event, groupsValue)); continue }
            let remaining = groups.compactMap { group -> OrderedJSON? in
                guard let hooks = group["hooks"]?.arrayValue else { return group }
                let others = hooks.filter { !isOwned($0["command"]?.stringValue ?? "") }
                if others.count == hooks.count { return group }
                return others.isEmpty ? nil : group.setting("hooks", to: .array(others))
            }
            if !remaining.isEmpty { kept.append((event, .array(remaining))) }
        }
        return root.setting("hooks", to: kept.isEmpty ? nil : .object(kept))
    }

    // MARK: - Dosya

    /// Bağlar ya da günceller; yedeğin yolunu döndürür (dosya yoksa nil).
    @discardableResult
    public static func connect(paths: Paths, settingsURL: URL = settingsURL, now: Date = .now) throws(Failure) -> URL? {
        try rewrite(settingsURL: settingsURL, now: now) { connecting($0, paths: paths) }
    }

    @discardableResult
    public static func disconnect(settingsURL: URL = settingsURL, now: Date = .now) throws(Failure) -> URL? {
        try rewrite(settingsURL: settingsURL, now: now) { disconnected($0) }
    }

    private static func rewrite(settingsURL: URL, now: Date, transform: (OrderedJSON) -> OrderedJSON) throws(Failure) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: settingsURL.deletingLastPathComponent().path) else { throw .claudeNotFound }
        let original = try? Data(contentsOf: settingsURL)
        let root: OrderedJSON
        if let original {
            // Okunamayan dosyaya dokunulmaz: kullanıcı elle bozmuş olabilir, ezmek veri kaybettirir.
            guard let parsed = try? OrderedJSON.parse(original), case .object = parsed else { throw .unreadable }
            root = parsed
        } else {
            root = .object([])
        }
        let updated = transform(root)
        let text = updated.serialized() + (original.map { $0.last == UInt8(ascii: "\n") } ?? true ? "\n" : "")
        let data = Data(text.utf8)
        if data == original { return nil }

        var backup: URL?
        if let original {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let url = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.browline-\(formatter.string(from: now)).bak")
            guard (try? original.write(to: url)) != nil else { throw .writeFailed }
            backup = url
        }
        let permissions = (try? fileManager.attributesOfItem(atPath: settingsURL.path))?[.posixPermissions]
        do {
            try data.write(to: settingsURL, options: .atomic)
            if let permissions { try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: settingsURL.path) }
            // Claude Code'un okuyacağı biçimde mi: standart ayrıştırıcıyla da doğrula.
            _ = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL))
        } catch {
            if let original { try? original.write(to: settingsURL, options: .atomic) }
            throw .writeFailed
        }
        Log.integrations.notice("Claude Code kancaları yazıldı (yedek \(backup == nil ? "yok" : "var", privacy: .public))")
        return backup
    }
}
