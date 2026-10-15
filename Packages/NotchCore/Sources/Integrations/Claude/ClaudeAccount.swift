import Foundation

/// Claude Code'un etkin hesabı: `~/.claude.json` içindeki `oauthAccount` profili (masaüstü
/// uygulamasının Code oturumları da aynı yapılandırma klasörünü kullanır). Yalnız gösterilecek
/// alanlar okunur; dosyada kimlik bilgisi aranmaz, okunmaz. Belgelenmiş bir biçim değil: alan
/// yoksa hesap gösterilmez.
public struct ClaudeAccount: Equatable, Sendable {
    public var email: String?
    public var displayName: String?
    public var organizationName: String?
    /// "Max 20x", "Pro", "Team"…; bilinmiyorsa nil.
    public var plan: String?
    /// Profilin Claude tarafından en son alındığı an.
    public var fetchedAt: Date?

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    public static func load(from url: URL = defaultURL) -> ClaudeAccount? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> ClaudeAccount? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            (account[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        let fetched = (account["profileFetchedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        let email = text("emailAddress")
        // Kişisel hesapta kuruluş adı "<e-posta>'s Organization": e-postayı tekrarlar, gösterilmez.
        let organization = text("organizationName").flatMap { name in
            email.map { name.localizedCaseInsensitiveContains($0) } == true ? nil : name
        }
        let result = ClaudeAccount(email: email, displayName: text("displayName") ?? text("fullName"),
                                   organizationName: organization,
                                   plan: planName(type: text("organizationType"),
                                                  tier: text("organizationRateLimitTier") ?? text("userRateLimitTier")),
                                   fetchedAt: fetched)
        return result.email == nil && result.displayName == nil ? nil : result
    }

    /// `claude_max` + `default_claude_max_20x` → "Max 20x"; tanınmayan türde nil.
    static func planName(type: String?, tier: String?) -> String? {
        guard let type = type?.lowercased() else { return nil }
        let multiplier = tier.flatMap { tier -> String? in
            guard let range = tier.range(of: #"\d+x"#, options: .regularExpression) else { return nil }
            return String(tier[range])
        }
        switch type {
        case "claude_max": return multiplier.map { "Max \($0)" } ?? "Max"
        case "claude_pro": return "Pro"
        case "claude_team", "team": return "Team"
        case "claude_enterprise", "enterprise": return "Enterprise"
        default: return nil
        }
    }
}
