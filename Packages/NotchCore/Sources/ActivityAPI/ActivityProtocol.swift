import Foundation

/// Dış dünyanın notch'a etkinlik göndermesi için protokol: yerel Unix soketi, satır başına bir JSON.
/// Örnek: `{"op":"push","id":"build","title":"Derleme","progress":0.4,"symbol":"hammer"}`
public enum ActivityAPI {
    /// Uygulama ile `notch` aracının buluştuğu soket. NOTCH_SOCKET ortam değişkeni ezer.
    public static var defaultSocketURL: URL {
        if let override = ProcessInfo.processInfo.environment["NOTCH_SOCKET"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.talatozcoban.browline/activity.sock")
    }

    /// Tek satırın üst sınırı; aşan bağlantı kapatılır.
    public static let maximumLineBytes = 16 * 1024
}

public struct ActivityRequest: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        /// Ekle ya da güncelle (aynı id).
        case push
        /// Kaldır.
        case end
        /// Kısa süreli bildirim; canlı etkinliklerin önüne geçer.
        case flash
        case list
        case ping
        /// Onay sorusu: bağlantı açık kalır, kullanıcı notch'tan yanıtlayınca `decision` döner.
        /// Bağlantı kapanırsa soru iptal edilir. Yalnız soket üzerinden (URL şemasında yanıt kanalı yok).
        case ask
        /// Bekleyen soruyu yanıtsız kapatır: soru başka yerde (ör. Claude'un kendi penceresinde) yanıtlandı.
        /// `id` `*` ile biterse önekle eşleşenlerin hepsi. Yalnız soket üzerinden.
        case dismiss
    }

    public var op: Operation
    public var id: String?
    public var title: String?
    public var subtitle: String?
    /// 0…1
    public var progress: Double?
    /// SF Symbols adı.
    public var symbol: String?
    /// #RRGGBB
    public var tint: String?
    /// 0…50; yerleşik etkinlikler: Now Playing 30, toplantı 40.
    public var priority: Int?
    /// Saniye; güncellenmeyen etkinlik bu süre sonunda kendiliğinden düşer.
    public var ttl: Double?
    /// flash için saniye.
    public var duration: Double?
    /// ask için uzun metin (ör. çalıştırılacak komut); en çok `ExternalQuestion.maximumDetailLength`.
    public var detail: String?
    /// ask: İzin ver/Reddet yerine seçenekler (ör. Claude'un AskUserQuestion sorusu); yanıt `selection`.
    public var choices: [String]?
    /// Seçeneklerin açıklamaları; varsa `choices` ile aynı sayıda.
    public var choiceDetails: [String]?
    /// Birden çok seçenek seçilebilir.
    public var multiple: Bool?

    public init(op: Operation, id: String? = nil, title: String? = nil, subtitle: String? = nil,
                progress: Double? = nil, symbol: String? = nil, tint: String? = nil, priority: Int? = nil,
                ttl: Double? = nil, duration: Double? = nil, detail: String? = nil,
                choices: [String]? = nil, choiceDetails: [String]? = nil, multiple: Bool? = nil) {
        self.detail = detail
        self.choices = choices
        self.choiceDetails = choiceDetails
        self.multiple = multiple
        self.op = op
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.symbol = symbol
        self.tint = tint
        self.priority = priority
        self.ttl = ttl
        self.duration = duration
    }
}

public struct ActivityResponse: Codable, Equatable, Sendable {
    /// ask yanıtı: yalnız kullanıcının tıklamasıyla. Süre dolarsa ya da "Claude'da yanıtla" seçilirse nil.
    public enum Decision: String, Codable, Sendable {
        case allow
        case deny
    }

    public var ok: Bool
    public var error: String?
    public var activities: [ExternalActivity]?
    public var decision: Decision?
    /// dismiss yanıtı: kapatılan soru sayısı.
    public var dismissed: Int?
    /// Seçenekli ask yanıtı: seçilen seçeneklerin sırası (0'dan). Yanıt yoksa nil.
    public var selection: [Int]?

    public static let success = ActivityResponse(ok: true)

    public init(ok: Bool, error: String? = nil, activities: [ExternalActivity]? = nil, decision: Decision? = nil,
                dismissed: Int? = nil, selection: [Int]? = nil) {
        self.ok = ok
        self.selection = selection
        self.error = error
        self.activities = activities
        self.decision = decision
        self.dismissed = dismissed
    }

    public static func failure(_ message: String) -> ActivityResponse { ActivityResponse(ok: false, error: message) }
}

/// Doğrulanmış dış etkinlik.
public struct ExternalActivity: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var progress: Double?
    public var symbol: String?
    public var tint: String?
    public var priority: Int
    public var updatedAt: Date
    public var expiresAt: Date

    public static let defaultPriority = 20
    public static let priorityRange = 0...50
    public static let defaultTTL: TimeInterval = 600
    public static let ttlRange: ClosedRange<TimeInterval> = 1...86_400
    public static let flashDurationRange: ClosedRange<TimeInterval> = 0.5...15

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        /// Alan ve dilden bağımsız kural ("≤ 80", "0…50", "#RRGGBB", "1…86400 s").
        case invalid(String, rule: String? = nil)

        public var description: String { description(in: .current) }

        public func description(in language: APILanguage) -> String {
            switch self {
            case let .missing(field): language.text("\(field) gerekli", "\(field) is required")
            case let .invalid(field, rule?): language.text("\(field) geçersiz (\(rule))", "\(field) is invalid (\(rule))")
            case let .invalid(field, nil): language.text("\(field) geçersiz", "\(field) is invalid")
            }
        }
    }

    /// İstemciden gelen alanları sınırlar içinde kabul eder; sınır dışını reddeder (sessizce kırpmaz).
    public static func validated(from request: ActivityRequest, now: Date = .now,
                                 requireID: Bool = true) throws(ValidationError) -> ExternalActivity {
        let id = request.id ?? "flash"
        if requireID {
            guard let given = request.id else { throw .missing("id") }
            guard given.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil else {
                throw .invalid("id", rule: "[A-Za-z0-9._-]{1,64}")
            }
        }
        guard let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw .missing("title")
        }
        guard title.count <= 80 else { throw .invalid("title", rule: "≤ 80") }
        if let subtitle = request.subtitle, subtitle.count > 120 { throw .invalid("subtitle", rule: "≤ 120") }
        if let progress = request.progress, !(0...1).contains(progress) || progress.isNaN {
            throw .invalid("progress", rule: "0…1")
        }
        if let symbol = request.symbol,
           symbol.range(of: #"^[a-z0-9.]{1,64}$"#, options: .regularExpression) == nil {
            throw .invalid("symbol", rule: "[a-z0-9.]{1,64}")
        }
        if let tint = request.tint, tint.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) == nil {
            throw .invalid("tint", rule: "#RRGGBB")
        }
        let priority = request.priority ?? defaultPriority
        guard priorityRange.contains(priority) else { throw .invalid("priority", rule: "0…50") }
        let ttl = request.ttl ?? defaultTTL
        guard ttlRange.contains(ttl) else { throw .invalid("ttl", rule: "1…86400 s") }
        return ExternalActivity(id: id, title: title, subtitle: request.subtitle, progress: request.progress,
                                symbol: request.symbol, tint: request.tint, priority: priority,
                                updatedAt: now, expiresAt: now.addingTimeInterval(ttl))
    }
}
