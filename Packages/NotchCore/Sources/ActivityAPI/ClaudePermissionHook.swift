import CryptoKit
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
        /// Araç adı + ana alanın (komut, dosya yolu, soru metni…) kısa özeti. Soru kimliğine girer; araç
        /// çalışınca (`PostToolUse`) kanca betiği aynısını hesaplayıp soruyu notch'tan düşürür: izin Claude'un
        /// kendi penceresinde verilmiş demektir. `PermissionRequest` girdisinde `tool_use_id` yok (belge).
        public var fingerprint: String
        /// AskUserQuestion: İzin ver/Reddet yerine seçenekli sorular.
        public var choiceQuestions: [ChoiceQuestion]
        /// `tool_input` olduğu gibi (JSON); yanıtlar `updatedInput` olarak buna eklenir.
        public var toolInputJSON: Data
    }

    public struct ChoiceQuestion: Equatable, Sendable {
        public struct Option: Equatable, Sendable {
            public var label: String
            public var description: String?
        }

        public var question: String
        public var header: String?
        public var options: [Option]
        public var multiSelect: Bool
    }

    /// Soru kimliği: `claude-perm-<oturum>-<parmak izi>-<rastgele>`. Kanca betiği (Examples/claude-code/
    /// notch-hook.sh) aynı oturum ve parmak izi kuralını uygular; değişirse ikisi birlikte değişmeli.
    public static func questionID(sessionPrefix: String, fingerprint: String, suffix: String? = nil) -> String {
        let session = sessionPrefix.isEmpty ? "x" : sessionPrefix
        let tail = suffix ?? String(UInt32.random(in: 0...UInt32.max), radix: 36)
        return "claude-perm-\(session)-\(fingerprint)-\(tail)"
    }

    /// `printf '%s\n%s' "$tool" "$key" | shasum -a 256 | cut -c1-10` ile aynı. Anahtar sonundaki satır sonları
    /// atılır (kabukta `$(…)` atıyor).
    public static func fingerprint(tool: String, key: String) -> String {
        var key = key
        while key.hasSuffix("\n") { key.removeLast() }
        let digest = SHA256.hash(data: Data("\(tool)\n\(key)".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(10))
    }

    /// Parmak izinin ana alanı; kanca betiğindeki `case` ile aynı tablo.
    static func fingerprintKey(tool: String, input: [String: Any]) -> String {
        switch tool {
        case "Bash": input["command"] as? String ?? ""
        case "Edit", "MultiEdit", "Write", "Read": input["file_path"] as? String ?? ""
        case "NotebookEdit": input["notebook_path"] as? String ?? ""
        case "WebFetch": input["url"] as? String ?? ""
        case "WebSearch": input["query"] as? String ?? ""
        case "AskUserQuestion": ((input["questions"] as? [[String: Any]])?.first?["question"] as? String) ?? ""
        default: ""
        }
    }

    /// Kanca girdisini okur; araç adı yoksa nil (o zaman soru sorulmaz).
    public static func parse(_ data: Data) -> Input? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = object["tool_name"] as? String, !tool.isEmpty else { return nil }
        let toolInput = object["tool_input"] as? [String: Any] ?? [:]
        let cwd = object["cwd"] as? String
        let session = (object["session_id"] as? String ?? "")
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return Input(toolName: tool,
                     summary: summary(tool: tool, input: toolInput, cwd: cwd),
                     project: cwd.map { ($0 as NSString).lastPathComponent },
                     sessionPrefix: String(session.prefix(8)),
                     fingerprint: fingerprint(tool: tool, key: fingerprintKey(tool: tool, input: toolInput)),
                     choiceQuestions: tool == "AskUserQuestion" ? choiceQuestions(in: toolInput) : [],
                     toolInputJSON: (try? JSONSerialization.data(withJSONObject: toolInput)) ?? Data("{}".utf8))
    }

    static func choiceQuestions(in input: [String: Any]) -> [ChoiceQuestion] {
        (input["questions"] as? [[String: Any]] ?? []).compactMap { item in
            guard let question = item["question"] as? String, !question.isEmpty else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> ChoiceQuestion.Option? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return ChoiceQuestion.Option(label: label, description: option["description"] as? String)
            }
            guard !options.isEmpty else { return nil }
            return ChoiceQuestion(question: question, header: item["header"] as? String, options: options,
                                  multiSelect: item["multiSelect"] as? Bool ?? false)
        }
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
    public static func request(for input: Input, timeout: TimeInterval, language: APILanguage) -> ActivityRequest {
        let id = questionID(sessionPrefix: input.sessionPrefix, fingerprint: input.fingerprint)
        let tool = displayName(for: input.toolName)
        let subtitle = [tool, input.project].compactMap { $0 }.joined(separator: " · ")
        return ActivityRequest(op: .ask, id: id,
                               title: language.text("Claude izin istiyor", "Claude needs permission"),
                               subtitle: String(subtitle.prefix(120)), symbol: "hand.raised.fill",
                               tint: "#D97757", ttl: timeout, detail: input.summary)
    }

    /// AskUserQuestion: soru başına bir seçenekli istek, sırayla sorulur. Uzun etiket ve açıklama notch için
    /// kısaltılır; yanıt sıra numarasıyla döndüğü için Claude'a özgün etiket gider.
    public static func choiceRequests(for input: Input, timeout: TimeInterval,
                                      language: APILanguage) -> [(question: ChoiceQuestion, request: ActivityRequest)] {
        let total = input.choiceQuestions.count
        let suffix = String(UInt32.random(in: 0...UInt32.max), radix: 36)
        return input.choiceQuestions.prefix(ExternalQuestion.maximumChoices).enumerated().map { index, question in
            let options = Array(question.options.prefix(ExternalQuestion.maximumChoices))
            let title = total > 1 ? language.text("Claude soruyor (\(index + 1)/\(total))", "Claude is asking (\(index + 1)/\(total))")
                                  : language.text("Claude soruyor", "Claude is asking")
            let subtitle = [question.header, input.project].compactMap { $0 }.joined(separator: " · ")
            let request = ActivityRequest(
                op: .ask, id: questionID(sessionPrefix: input.sessionPrefix, fingerprint: input.fingerprint,
                                         suffix: "\(suffix)q\(index + 1)"),
                title: title,
                subtitle: String(subtitle.prefix(120)), symbol: "questionmark.bubble.fill", tint: "#D97757",
                ttl: timeout, detail: String(question.question.prefix(ExternalQuestion.maximumDetailLength)),
                choices: options.map { String($0.label.prefix(ExternalQuestion.maximumChoiceLength)) },
                choiceDetails: options.map { String(($0.description ?? "").prefix(ExternalQuestion.maximumChoiceDetailLength)) },
                multiple: question.multiSelect)
            return (question, request)
        }
    }

    /// AskUserQuestion yanıtı: izin + `updatedInput` (özgün `tool_input` ve `answers`: soru metni → seçilen
    /// etiket; çoklu seçimde ", " ile). Agent SDK'nın belgelediği biçim; kanca için belgelenmemiş, canlı denendi.
    public static func answerOutput(answers: [String: String], toolInputJSON: Data) -> String? {
        var updated = (try? JSONSerialization.jsonObject(with: toolInputJSON) as? [String: Any]) ?? [:]
        updated["answers"] = answers
        let decision: [String: Any] = ["behavior": "allow", "updatedInput": updated]
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// MCP araç adını okunur yapar: mcp__sunucu__araç → "sunucu › araç".
    static func displayName(for tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return tool }
        let parts = tool.dropFirst(5).components(separatedBy: "__")
        return parts.joined(separator: " › ")
    }

    /// Kanca çıktısı; karar yoksa nil (hiçbir şey yazılmaz).
    public static func output(for decision: ActivityResponse.Decision?, language: APILanguage) -> String? {
        guard let decision else { return nil }
        var body: [String: Any] = ["behavior": decision.rawValue]
        if decision == .deny {
            body["message"] = language.text("Kullanıcı bu isteği notch'tan reddetti.", "The user denied this request from the notch.")
        }
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
