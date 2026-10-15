import Foundation

/// Claude Code oturum kayıtlarından "limit doldu" bilgisi. Kayıtlarda kullanım yüzdesi yok; yalnız
/// limit dolunca dönen hata satırında `rate_limit_info` (tür, sıfırlanma zamanı) var. Masaüstü
/// uygulamasının oturumları da buraya yazar. Belgelenmiş bir biçim değil: bulunamazsa sessizce boş.
public struct ClaudeLimitHit: Equatable, Sendable {
    /// "five_hour", "seven_day", "seven_day_opus"…
    public var type: String
    public var resetsAt: Date
    public var hitAt: Date?

    public init(type: String, resetsAt: Date, hitAt: Date? = nil) {
        self.type = type
        self.resetsAt = resetsAt
        self.hitAt = hitAt
    }

    /// Sekmede gösterilecek ad.
    public var isWeekly: Bool { type.hasPrefix("seven_day") }
    /// "seven_day_opus" → "Opus"; düz pencerede nil.
    public var modelSuffix: String? {
        guard let range = type.range(of: "seven_day_") else { return nil }
        let rest = type[range.upperBound...]
        return rest.isEmpty ? nil : rest.prefix(1).uppercased() + rest.dropFirst()
    }
}

public final class ClaudeLimitLog: @unchecked Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Haftalık pencere en uzunu; daha eski kayıt etkin bir limit taşıyamaz.
    static let lookback: TimeInterval = 7 * 24 * 60 * 60
    static let maximumFiles = 24
    /// Limit dolunca oturum genelde orada durur; dosyanın yalnız sonu okunur.
    static let tailBytes = 256 * 1024

    private let directory: URL
    private let lock = NSLock()
    /// Değişmeyen dosya yeniden okunmaz: yol → (değişme zamanı, bulunanlar).
    private var cache: [String: (Date, [ClaudeLimitHit])] = [:]

    public init(directory: URL = ClaudeLimitLog.defaultDirectory) {
        self.directory = directory
    }

    /// Şu an etkin (sıfırlanma zamanı gelmemiş) limitler; türe göre en yenisi, sıfırlanmaya göre sıralı.
    public func activeHits(now: Date = .now) -> [ClaudeLimitHit] {
        let since = now.addingTimeInterval(-Self.lookback)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var recent: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= since else { continue }
            recent.append((url, modified))
        }
        recent.sort { $0.1 > $1.1 }
        var hits: [ClaudeLimitHit] = []
        for (url, modified) in recent.prefix(Self.maximumFiles) {
            hits += scan(url, modified: modified)
        }
        var latestByType: [String: ClaudeLimitHit] = [:]
        for hit in hits where hit.resetsAt > now {
            if let existing = latestByType[hit.type], existing.resetsAt >= hit.resetsAt { continue }
            latestByType[hit.type] = hit
        }
        return latestByType.values.sorted { $0.resetsAt > $1.resetsAt }
    }

    private func scan(_ url: URL, modified: Date) -> [ClaudeLimitHit] {
        lock.lock()
        if let cached = cache[url.path], cached.0 == modified { lock.unlock(); return cached.1 }
        lock.unlock()
        var found: [ClaudeLimitHit] = []
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            let start = size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0
            try? handle.seek(toOffset: start)
            if let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n") where line.contains("rate_limit_info") || line.contains("quotaLimits") {
                    if let hit = Self.parse(line: String(line)) { found.append(hit) }
                }
            }
        }
        lock.lock()
        cache[url.path] = (modified, found)
        lock.unlock()
        return found
    }

    /// Tek kayıt satırı → limit; `apiErrorParams.rate_limit_info` ya da `quotaLimits` (ikisi aynı).
    /// Yalnız "rejected" (doldu) sayılır.
    static func parse(line: String) -> ClaudeLimitHit? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let info = ((object["apiErrorParams"] as? [String: Any])?["rate_limit_info"] as? [String: Any])
            ?? (object["quotaLimits"] as? [String: Any])
        guard let info, info["status"] as? String == "rejected",
              let type = info["rateLimitType"] as? String,
              let resets = (info["resetsAt"] as? NSNumber)?.doubleValue else { return nil }
        let hitAt = (object["timestamp"] as? String).flatMap { ISO8601DateFormatter.fractional.date(from: $0) }
        return ClaudeLimitHit(type: type, resetsAt: Date(timeIntervalSince1970: resets), hitAt: hitAt)
    }
}

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
