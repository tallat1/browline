import Foundation
import Observation

/// Dışarıdan gelen onay sorusu (ör. Claude Code izin istemi). Notch'ta düğmelerle yanıtlanır.
public struct ExternalQuestion: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var detail: String?
    public var symbol: String?
    public var tint: String?
    public var askedAt: Date
    public var expiresAt: Date

    public static let maximumDetailLength = 2000
    /// Kanca zaman aşımından (Claude'da varsayılan 600 sn) önce düşsün.
    public static let defaultTTL: TimeInterval = 110
    public static let ttlRange: ClosedRange<TimeInterval> = 1...590

    /// Başlık, alt başlık, simge ve renk etkinlikle aynı kurallarla; ayrıntı ve süre ayrıca.
    public static func validated(from request: ActivityRequest, now: Date = .now)
        throws(ExternalActivity.ValidationError) -> ExternalQuestion {
        let base = try ExternalActivity.validated(from: request, now: now)
        if let detail = request.detail, detail.count > maximumDetailLength {
            throw .invalid("detail", rule: "≤ \(maximumDetailLength)")
        }
        let ttl = request.ttl ?? defaultTTL
        guard ttlRange.contains(ttl) else { throw .invalid("ttl", rule: "1…590 s") }
        return ExternalQuestion(id: base.id, title: base.title, subtitle: base.subtitle, detail: request.detail,
                                symbol: base.symbol, tint: base.tint, askedAt: now,
                                expiresAt: now.addingTimeInterval(ttl))
    }
}

/// Bekleyen sorular. Her soru bir bekleyen istek: kullanıcı yanıtlayınca, süre dolunca ya da istemci
/// bağlantıyı kapatınca (görev iptali) çözülür. Karar yalnız `answer` ile verilir; kendiliğinden
/// verilen tek sonuç "yanıt yok" (nil), yani istemci kendi akışına döner.
@MainActor
@Observable
public final class QuestionStore {
    public private(set) var questions: [ExternalQuestion] = []
    /// Kapalıysa soru gösterilmez, hemen "yanıt yok" döner.
    @ObservationIgnored public var isEnabled = true
    @ObservationIgnored public var onQuestionsChanged: (([ExternalQuestion]) -> Void)?
    /// Soru nasıl kapandı: tanı için (ör. masaüstü uygulamasında yanıtlanınca kanca kapatılıyor mu).
    @ObservationIgnored public var onResolved: ((ExternalQuestion, ActivityResponse.Decision?, Resolution) -> Void)?

    public enum Resolution: String, Sendable {
        /// Kullanıcı notch'ta yanıtladı (karar nil ise "uygulamada yanıtla").
        case answered
        /// Süre doldu.
        case expired
        /// İstemci bağlantıyı kapattı (kanca öldürüldü ya da yanıt başka yerden geldi).
        case cancelled
    }
    @ObservationIgnored private var waiters: [String: CheckedContinuation<ActivityResponse.Decision?, Never>] = [:]
    @ObservationIgnored private var expiryTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var resolvedEarly: Set<String> = []

    public static let maximumQuestions = 8

    public init() {}

    /// Şu an gösterilen soru (en eskisi).
    public var current: ExternalQuestion? { questions.first }

    public func ask(_ request: ActivityRequest, now: Date = .now) async -> ActivityResponse {
        guard isEnabled else { return ActivityResponse(ok: true) }
        let question: ExternalQuestion
        do {
            question = try ExternalQuestion.validated(from: request, now: now)
        } catch {
            return .failure(error.description)
        }
        guard !questions.contains(where: { $0.id == question.id }) else { return .failure(APILanguage.current.text("\(question.id) zaten bekliyor", "\(question.id) is already waiting")) }
        guard questions.count < Self.maximumQuestions else { return .failure(APILanguage.current.text("en çok \(Self.maximumQuestions) soru bekleyebilir", "at most \(Self.maximumQuestions) questions can wait")) }
        questions.append(question)
        onQuestionsChanged?(questions)
        let id = question.id
        expiryTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, question.expiresAt.timeIntervalSince(now))))
            guard !Task.isCancelled else { return }
            self?.resolve(id, with: nil, reason: .expired)
        }
        let decision = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ActivityResponse.Decision?, Never>) in
                if resolvedEarly.remove(id) != nil {
                    continuation.resume(returning: nil)
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resolve(id, with: nil, reason: .cancelled) }
        }
        return ActivityResponse(ok: true, decision: decision)
    }

    /// Kullanıcının yanıtı; nil = "kendi akışında yanıtla" (istemci normal yoluna döner).
    public func answer(_ id: String, with decision: ActivityResponse.Decision?) {
        resolve(id, with: decision, reason: .answered)
    }

    private func resolve(_ id: String, with decision: ActivityResponse.Decision?, reason: Resolution) {
        guard let question = questions.first(where: { $0.id == id }) else { return }
        questions.removeAll { $0.id == id }
        onResolved?(question, decision, reason)
        expiryTasks.removeValue(forKey: id)?.cancel()
        if let waiter = waiters.removeValue(forKey: id) {
            waiter.resume(returning: decision)
        } else {
            // Görev iptali beklemeye girilmeden geldiyse: bekleme başlarken hemen çözülsün.
            resolvedEarly.insert(id)
        }
        onQuestionsChanged?(questions)
    }
}
