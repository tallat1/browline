import Foundation

/// ⚠️ BELGELENMEMİŞ: Claude Code'un `/usage` komutunun kullandığı plan kullanım uç noktası.
/// Kullanıcı riskleri kabul edip açıkça istedi (2026-10-16). Haber vermeden değişebilir; sık 429
/// döndürdüğü bildirildi.
///
/// Kimlik: Claude Code'un Anahtar Zinciri kaydı ("Claude Code-credentials"), yoksa
/// `~/.claude/.credentials.json`. Anahtar yalnız bu isteğin başlığına konur ve süresi dolana kadar
/// BELLEKTE tutulur; diske yazılmaz, günlüğe yazılmaz, başka yere gönderilmez. Süresi dolmuş anahtar
/// YENİLENMEZ: yenileme anahtarı döndürür, Claude Code'un kendi kaydı bozulur. Yenilemeyi Claude Code
/// yapar (terminalde `claude` çalışınca).
///
/// Anahtar Zinciri `/usr/bin/security` ile okunur, Claude Code'un kendisi gibi (ikili dosyasında
/// `security add-generic-password -U … -X` / `find-generic-password`, 2026-10-16). Kayıt bu araçla
/// yazıldığı için ona güvenir, pencere çıkmaz. Doğrudan `SecItemCopyMatching` her okumada "NotchMVP
/// anahtara erişmek istiyor" diye soruyordu; Claude Code anahtarı yeniledikçe kaydı yeniden yazdığı
/// için "Always Allow" da siliniyordu (kullanıcı: "sürekli geliyor"). Kullanıcı bu yolu seçti; bedeli
/// macOS'un uygulama başına onayının devreden çıkması (aynı kullanıcının her süreci zaten okuyabiliyor).
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

    struct Credentials: Equatable, Sendable {
        let accessToken: String
        let expiresAt: Date?

        func isValid(at now: Date) -> Bool { expiresAt.map { $0 > now } ?? true }
    }

    /// Okunan anahtar süresi dolana ya da reddedilene kadar bellekte: 5 dakikalık döngü her seferinde
    /// Anahtar Zinciri'ne gitmez.
    actor CredentialCache {
        private var credentials: Credentials?

        func current(at now: Date) -> Credentials? {
            guard let credentials, credentials.isValid(at: now) else { return nil }
            return credentials
        }

        func store(_ credentials: Credentials?) { self.credentials = credentials }
    }

    static let cache = CredentialCache()

    /// Ağ ve alt süreç beklettiği için ana iş parçacığında çağrılmaz.
    public static func fetch(now: Date = .now) async -> Result<ClaudeUsageMonitor.Usage, Failure> {
        if let cached = await cache.current(at: now) {
            let result = await request(with: cached, now: now)
            // Claude Code anahtarı süresinden önce yenilediyse eskisi reddedilir: bir kez yeniden oku.
            guard result == .failure(.unauthorized) else { return result }
            await cache.store(nil)
            guard let fresh = readCredentials(), fresh != cached else { return result }
            return await request(validating: fresh, now: now)
        }
        guard let credentials = readCredentials() else { return .failure(.noCredentials) }
        return await request(validating: credentials, now: now)
    }

    private static func request(validating credentials: Credentials,
                                now: Date) async -> Result<ClaudeUsageMonitor.Usage, Failure> {
        guard credentials.isValid(at: now) else { return .failure(.expired) }
        await cache.store(credentials)
        let result = await request(with: credentials, now: now)
        if result == .failure(.unauthorized) { await cache.store(nil) }
        return result
    }

    private static func request(with credentials: Credentials, now: Date) async -> Result<ClaudeUsageMonitor.Usage, Failure> {
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
            Log.integrations.notice("Claude anahtarı okundu (bellekte, süresi dolana kadar)")
            return credentials
        }
        return nil
    }

    /// `security find-generic-password -s … -w`: parola stdout'a, oradan yalnız bu sürecin belleğine.
    /// Takılırsa (beklenmedik pencere) 10 sn sonra sonlandırılır.
    private static func keychainData() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            Log.integrations.error("security çalıştırılamadı: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else {
            // 44: kayıt yok (oturum açılmamış).
            if process.terminationStatus != 44 {
                Log.integrations.error("Claude Anahtar Zinciri okunamadı: security çıkış \(process.terminationStatus)")
            }
            return nil
        }
        return decodePassword(data)
    }

    /// `-w` yazdırılabilir parolayı düz, değilse onaltılık basar; sondaki satır sonu atılır.
    static func decodePassword(_ output: Data) -> Data? {
        var text = String(decoding: output, as: UTF8.self)
        while text.last?.isNewline == true { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if text.first == "{" { return Data(text.utf8) }
        guard text.count.isMultiple(of: 2), text.allSatisfy(\.isHexDigit) else { return Data(text.utf8) }
        var bytes = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
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
