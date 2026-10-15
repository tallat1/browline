import Foundation
import Security

/// ⚠️ BELGELENMEMİŞ: Claude Code'un `/usage` komutunun kullandığı plan kullanım uç noktası.
/// Kullanıcı riskleri kabul edip açıkça istedi (2026-10-16). Haber vermeden değişebilir; sık 429
/// döndürdüğü bildirildi.
///
/// Kimlik: Claude Code'un Anahtar Zinciri kaydı ("Claude Code-credentials"), yoksa
/// `~/.claude/.credentials.json`. Anahtar yalnız bu isteğin başlığına konur; saklanmaz, günlüğe
/// yazılmaz, başka yere gönderilmez. Süresi dolmuş anahtar YENİLENMEZ: yenileme anahtarı döndürür,
/// Claude Code'un kendi kaydı bozulur. Yenilemeyi Claude Code yapar (terminalde `claude` çalışınca).
public enum ClaudeUsageAPI {
    public enum Failure: Error, Equatable, Sendable {
        /// Terminalde oturum açılmamış ya da Anahtar Zinciri erişimine izin verilmedi.
        case noCredentials
        /// Anahtarın süresi dolmuş; Claude Code yenileyene kadar istek atılmaz.
        case expired
        /// 401/403: anahtar reddedildi.
        case unauthorized
        /// 429: çok fazla istek.
        case rateLimited(retryAfter: TimeInterval?)
        case badResponse(Int)
        case network(String)
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    struct Credentials {
        let accessToken: String
        let expiresAt: Date?
    }

    /// Ağ ve Anahtar Zinciri (ilk seferde izin penceresi) beklettiği için ana iş parçacığında çağrılmaz.
    public static func fetch(now: Date = .now) async -> Result<ClaudeUsageMonitor.Usage, Failure> {
        guard let credentials = readCredentials() else { return .failure(.noCredentials) }
        if let expiresAt = credentials.expiresAt, expiresAt <= now { return .failure(.expired) }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                guard let usage = parse(data, capturedAt: now) else {
                    let keys = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?.keys.sorted() ?? []
                    Log.integrations.error("Claude kullanım yanıtı çözülemedi; alanlar: \(keys.joined(separator: ","), privacy: .public)")
                    return .failure(.badResponse(status))
                }
                return .success(usage)
            case 401, 403:
                return .failure(.unauthorized)
            case 429:
                let retry = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                return .failure(.rateLimited(retryAfter: retry))
            default:
                return .failure(.badResponse(status))
            }
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// Önbellek ve çerez tutmayan oturum: anahtarlı yanıt diske düşmesin.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    // MARK: - Kimlik

    private static func readCredentials() -> Credentials? {
        if let data = keychainData() ?? fileData(), let credentials = parseCredentials(data) {
            return credentials
        }
        return nil
    }

    /// İlk okumada macOS "NotchMVP, anahtar zincirindeki … anahtarına erişmek istiyor" diye sorar.
    private static func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess, status != errSecItemNotFound {
            Log.integrations.error("Claude Anahtar Zinciri okunamadı: \(status)")
        }
        return status == errSecSuccess ? result as? Data : nil
    }

    private static func fileData() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }

    /// `{"claudeAiOauth":{"accessToken":…,"expiresAt":<ms>}}`. Yenileme anahtarı okunmaz.
    static func parseCredentials(_ data: Data) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(accessToken: token, expiresAt: expires)
    }

    // MARK: - Yanıt

    /// `{"five_hour":{"utilization":12.0,"resets_at":"…+00:00"},"seven_day":{…},…}`; yüzde 0–100.
    static func parse(_ data: Data, capturedAt: Date) -> ClaudeUsageMonitor.Usage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ key: String) -> ClaudeUsageMonitor.Window? {
            guard let value = root[key] as? [String: Any],
                  let utilization = (value["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (value["resets_at"] as? String).flatMap(date(from:))
            return ClaudeUsageMonitor.Window(usedPercentage: min(max(utilization, 0), 100), resetsAt: reset)
        }
        let fiveHour = window("five_hour"), sevenDay = window("seven_day")
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return ClaudeUsageMonitor.Usage(fiveHour: fiveHour, sevenDay: sevenDay, capturedAt: capturedAt)
    }

    /// Mikro saniyeli ISO 8601 ("2026-10-16T04:59:59.943648+00:00") dahil.
    static func date(from text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        // Kesirli kısım atılır: ISO8601DateFormatter 6 haneli kesri her zaman çözemiyor.
        guard let dot = text.firstIndex(of: "."),
              let zone = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) else { return nil }
        return plain.date(from: String(text[..<dot]) + String(text[zone...]))
    }
}
