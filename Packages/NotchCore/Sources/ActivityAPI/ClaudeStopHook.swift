import Foundation

/// Claude Code `Stop` kancası (`notch claude-stop`): tur Claude masaüstünün karar kutusuyla bittiyse kutu notch'ta
/// "Claude seni bekliyor" kartı olarak görünür, düğmesi oturumu Claude'da açar.
///
/// Kutu, masaüstünün `mcp__ccd_turn__wrap_up` aracı: girdisinde `recap`, `ask` ve düğmeler (`actions[].label`)
/// var ve oturum kaydına (`transcript_path`, JSONL) yazılıyor. Yanıt notch'tan verilemez: Claude var olan bir
/// oturuma dışarıdan mesaj göndermeye izin vermiyor (`claude://code/new?q=` yalnız yeni oturum); kart yalnız
/// `claude://code/continue?session=local_…` ile doğru oturumu açar (`needs-input` yalnız izin bekleyenleri tanıyor). Kanca kimliği (`session_id`) ile masaüstü
/// kimliği (`local_…`) arasındaki eşleme masaüstünün oturum dosyalarında (`cliSessionId`). Araç, bağlantı ve
/// dosyalar belgelenmemiş (2026-10-17, Claude masaüstü + Claude Code 2.1.295); bulunamazsa kart yok, kanca
/// "Claude bitti" bildirimine döner.
public enum ClaudeStopHook {
    public struct Input: Equatable, Sendable {
        public var sessionID: String
        public var sessionPrefix: String
        public var transcriptPath: String?
        public var project: String?
    }

    /// Masaüstünün karar kutusu.
    public struct Decision: Equatable, Sendable {
        public var ask: String
        public var recap: String?
        /// Düğme etiketleri; notch'ta yalnız bilgi (tıklanınca yanıt gitmez).
        public var options: [String]
    }

    public static let decisionTool = "mcp__ccd_turn__wrap_up"
    /// Kart, oturumdaki yeni istemle (kanca betiği `dismiss claude-perm-<oturum>-*`) ya da bu sürede düşer.
    public static let cardTTL: TimeInterval = 1800

    public static var desktopSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    public static func parse(_ data: Data) -> Input? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = object["session_id"] as? String, !session.isEmpty else { return nil }
        let prefix = session.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8)
        return Input(sessionID: session, sessionPrefix: String(prefix),
                     transcriptPath: object["transcript_path"] as? String,
                     project: (object["cwd"] as? String).map { ($0 as NSString).lastPathComponent })
    }

    // MARK: - Oturum kaydı

    /// Kaydın sonundan okur: kutu turun son araçlarından biri. Kayıt onlarca MB olabilir.
    public static func decision(transcript url: URL, tailBytes: Int = 1 << 20) -> Decision? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return nil }
        return decision(inTail: data, isPartial: offset > 0)
    }

    /// Sondan geriye: bu turun karar kutusu (`ask` doluysa). Önce kullanıcı istemine varılırsa ya da kutu
    /// sorusuz kapandıysa nil. Araç sonuçları da `user` satırı; istem sayılmaz.
    static func decision(inTail data: Data, isPartial: Bool) -> Decision? {
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if isPartial, !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = entry["message"] as? [String: Any] else { continue }
            switch entry["type"] as? String {
            case "user":
                if isPrompt(message["content"]) { return nil }
            case "assistant":
                let blocks = message["content"] as? [[String: Any]] ?? []
                guard let call = blocks.last(where: { $0["type"] as? String == "tool_use" && $0["name"] as? String == decisionTool }),
                      let input = call["input"] as? [String: Any] else { continue }
                return decision(from: input)
            default:
                continue
            }
        }
        return nil
    }

    static func decision(from input: [String: Any]) -> Decision? {
        guard let ask = (input["ask"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty else { return nil }
        var actions = input["actions"] as? [[String: Any]]
        if actions == nil, let text = input["actions"] as? String, let data = text.data(using: .utf8) {
            actions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        }
        let options = (actions ?? []).compactMap { action -> String? in
            let label = (action["label"] as? String ?? action["action"] as? String)?.trimmingCharacters(in: .whitespaces)
            return label?.isEmpty == false ? label : nil
        }
        let recap = (input["recap"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Decision(ask: ask, recap: recap?.isEmpty == false ? recap : nil, options: options)
    }

    private static func isPrompt(_ content: Any?) -> Bool {
        if let text = content as? String { return !text.isEmpty }
        guard let blocks = content as? [[String: Any]] else { return false }
        return blocks.contains { $0["type"] as? String != "tool_result" }
    }

    // MARK: - Masaüstü oturumu

    /// Kanca oturumunun masaüstü kimliği (`local_…`); en son değişen dosyadan başlar. Yoksa nil (terminal oturumu).
    public static func desktopSessionID(forCLISession id: String, in root: URL = desktopSessionsDirectory) -> String? {
        let fileManager = FileManager.default
        guard !id.isEmpty, let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("local_") && url.pathExtension == "json" {
            files.append((url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast))
        }
        let needle = Data(id.utf8)
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }) {
            guard let data = try? Data(contentsOf: url), data.range(of: needle) != nil,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["cliSessionId"] as? String == id,
                  let session = object["sessionId"] as? String, isDesktopSessionID(session) else { continue }
            return session
        }
        return nil
    }

    /// Masaüstünün bağlantıda kabul ettiği biçim.
    public static func isDesktopSessionID(_ value: String) -> Bool {
        value.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil
    }

    // MARK: - Notch isteği

    /// Kart kimliği izin sorularıyla aynı önekte: kanca betiği yeni istemde ve oturum sonunda hepsini düşürür.
    public static func cardID(sessionPrefix: String) -> String {
        "claude-perm-\(sessionPrefix.isEmpty ? "x" : sessionPrefix)-turn"
    }

    public static func request(for input: Input, decision: Decision, desktopSession: String?,
                               language: APILanguage = .current) -> ActivityRequest {
        ActivityRequest(
            op: .handoff, id: cardID(sessionPrefix: input.sessionPrefix),
            title: language.text("Claude seni bekliyor", "Claude is waiting for you"),
            subtitle: input.project.map { String($0.prefix(120)) },
            symbol: "bubble.left.and.text.bubble.right.fill", tint: "#D97757", ttl: cardTTL,
            detail: String(decision.ask.prefix(ExternalQuestion.maximumDetailLength)),
            choices: decision.options.prefix(ExternalQuestion.maximumChoices)
                .map { String($0.prefix(ExternalQuestion.maximumChoiceLength)) },
            context: decision.recap.map { String($0.prefix(ExternalQuestion.maximumContextLength)) },
            session: desktopSession)
    }
}
