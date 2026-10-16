import Foundation

/// Claude Code `PermissionRequest` kancası ile notch sorusu arasındaki çeviri (`notch claude-permission`).
///
/// Belge: https://code.claude.com/docs/en/hooks (PermissionRequest decision control, 2026-10-16).
/// Kanca girdisi stdin'de: `tool_name`, `tool_input`, `cwd`, `session_id`… Karar çıktısı:
/// `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`.
/// Karar yoksa hiçbir şey yazılmaz: Claude kendi izin penceresiyle devam eder. Kalıcı izin kuralı
/// (`updatedPermissions`) bilerek hiç yazılmaz; notch yalnız tek seferlik izin verir ya da reddeder.
public enum ClaudePermissionHook {
    public struct Input: Equatable, Sendable {
        public var toolName: String
        public var summary: String
        public var project: String?
        public var sessionPrefix: String
    }

    /// Kanca girdisini okur; araç adı yoksa nil (o zaman soru sorulmaz).
    public static func parse(_ data: Data) -> Input? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = object["tool_name"] as? String, !tool.isEmpty else { return nil }
        let toolInput = object["tool_input"] as? [String: Any] ?? [:]
        let cwd = object["cwd"] as? String
        let session = (object["session_id"] as? String ?? "")
            .filter { $0.isLetter || $0.isNumber }
        return Input(toolName: tool,
                     summary: summary(tool: tool, input: toolInput, cwd: cwd),
                     project: cwd.map { ($0 as NSString).lastPathComponent },
                     sessionPrefix: String(session.prefix(8)))
    }

    /// Soruda gösterilecek okunur özet: komut, dosya yolu, adres…
    static func summary(tool: String, input: [String: Any], cwd: String?) -> String {
        func string(_ key: String) -> String? {
            (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        func path(_ value: String) -> String {
            guard let cwd, value.hasPrefix(cwd + "/") else { return value }
            return String(value.dropFirst(cwd.count + 1))
        }
        var text: String
        switch tool {
        case "Bash":
            text = string("command") ?? ""
            if let description = string("description") { text += "\n# " + description }
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit":
            text = (string("file_path") ?? string("notebook_path")).map(path) ?? compactJSON(input)
        case "WebFetch":
            text = string("url") ?? compactJSON(input)
        case "WebSearch":
            text = string("query") ?? compactJSON(input)
        case "Glob", "Grep":
            text = [string("pattern"), string("path").map(path)].compactMap { $0 }.joined(separator: "  ")
        default:
            text = compactJSON(input)
        }
        if text.isEmpty { text = tool }
        if text.count > ExternalQuestion.maximumDetailLength {
            text = String(text.prefix(ExternalQuestion.maximumDetailLength - 1)) + "…"
        }
        return text
    }

    private static func compactJSON(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Notch'a gidecek soru. Kimlik oturuma ve isteğe özgü; başlık sistem diline göre.
    public static func request(for input: Input, timeout: TimeInterval, turkish: Bool) -> ActivityRequest {
        let suffix = String(UInt32.random(in: 0...UInt32.max), radix: 36)
        let id = "claude-perm-\(input.sessionPrefix.isEmpty ? "x" : input.sessionPrefix)-\(suffix)"
        let tool = displayName(for: input.toolName)
        let subtitle = [tool, input.project].compactMap { $0 }.joined(separator: " · ")
        return ActivityRequest(op: .ask, id: id,
                               title: turkish ? "Claude izin istiyor" : "Claude needs permission",
                               subtitle: String(subtitle.prefix(120)), symbol: "hand.raised.fill",
                               tint: "#D97757", ttl: timeout, detail: input.summary)
    }

    /// MCP araç adını okunur yapar: mcp__sunucu__araç → "sunucu › araç".
    static func displayName(for tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return tool }
        let parts = tool.dropFirst(5).components(separatedBy: "__")
        return parts.joined(separator: " › ")
    }

    /// Kanca çıktısı; karar yoksa nil (hiçbir şey yazılmaz).
    public static func output(for decision: ActivityResponse.Decision?, turkish: Bool) -> String? {
        guard let decision else { return nil }
        var body: [String: Any] = ["behavior": decision.rawValue]
        if decision == .deny {
            body["message"] = turkish ? "Kullanıcı bu isteği notch'tan reddetti." : "The user denied this request from the notch."
        }
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
