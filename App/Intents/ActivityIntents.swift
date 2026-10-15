import ActivityAPI
import AppIntents

// Kestirmeler eylemleri. Soketi dolaşmadan koordinatörün işleyicisine girer: sokette ve URL
// şemasında olduğu gibi aynı doğrulama ve aynı "Etkinlik API'si açık mı" ayarı. Uygulamayı öne
// almaz (openAppWhenRun false); çalışmıyorsa sistem arka planda açar.

struct ShowActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Notch'ta etkinlik göster"
    static let description = IntentDescription(
        "Notch'ta bir etkinlik gösterir; aynı kimlikle yeniden çalıştırmak onu günceller.")

    @Parameter(title: "Kimlik", description: "Harf, rakam, nokta, tire; en çok 64 karakter.")
    var identifier: String

    @Parameter(title: "Başlık")
    var title: String

    @Parameter(title: "Alt başlık")
    var subtitle: String?

    @Parameter(title: "İlerleme (%)", inclusiveRange: (0, 100))
    var progressPercent: Int?

    @Parameter(title: "SF Symbol adı", description: "Örnek: hammer, checkmark.circle.fill")
    var symbol: String?

    @Parameter(title: "Renk", description: "#RRGGBB, örnek #FF9F0A")
    var tint: String?

    @Parameter(title: "Öncelik", description: "0–50; çalan müzik 30, toplantı 40.",
               default: 20, inclusiveRange: (0, 50))
    var priority: Int

    @Parameter(title: "Süre (saniye)", description: "Güncellenmezse bu sürenin sonunda kendiliğinden düşer.",
               default: 600, inclusiveRange: (1, 86_400))
    var timeToLive: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Notch'ta \(\.$title) göster") {
            \.$identifier
            \.$subtitle
            \.$progressPercent
            \.$symbol
            \.$tint
            \.$priority
            \.$timeToLive
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try ActivityIntentRunner.run(ActivityRequest(
            op: .push, id: identifier, title: title, subtitle: subtitle,
            progress: progressPercent.map { Double($0) / 100 }, symbol: symbol, tint: tint,
            priority: priority, ttl: Double(timeToLive)))
        return .result()
    }
}

struct EndActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Notch etkinliğini bitir"
    static let description = IntentDescription("Kimliği verilen etkinliği notch'tan kaldırır.")

    @Parameter(title: "Kimlik")
    var identifier: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$identifier) etkinliğini bitir")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try ActivityIntentRunner.run(ActivityRequest(op: .end, id: identifier))
        return .result()
    }
}

struct FlashActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Notch'ta kısa bildirim göster"
    static let description = IntentDescription("Birkaç saniyelik bildirim; diğer etkinliklerin önüne geçer.")

    @Parameter(title: "Başlık")
    var title: String

    @Parameter(title: "Alt başlık")
    var subtitle: String?

    @Parameter(title: "SF Symbol adı")
    var symbol: String?

    @Parameter(title: "Renk", description: "#RRGGBB")
    var tint: String?

    @Parameter(title: "Süre (saniye)", default: 3, inclusiveRange: (1, 15))
    var duration: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Notch'ta \(\.$title) bildir") {
            \.$subtitle
            \.$symbol
            \.$tint
            \.$duration
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try ActivityIntentRunner.run(ActivityRequest(
            op: .flash, title: title, subtitle: subtitle, symbol: symbol, tint: tint, duration: Double(duration)))
        return .result()
    }
}

/// Kestirmeler'in hata olarak gösterdiği metin.
struct ActivityIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

@MainActor
enum ActivityIntentRunner {
    static func run(_ request: ActivityRequest) throws {
        guard let coordinator = AppCoordinator.current else {
            throw ActivityIntentError(message: String(localized: "NotchMVP henüz hazır değil; birazdan yeniden deneyin."))
        }
        let response = coordinator.handleExternal(request, source: "Kestirme")
        guard response.ok else { throw ActivityIntentError(message: response.error ?? "") }
    }
}
