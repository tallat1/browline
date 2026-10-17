import Foundation
import Observation

/// Dışarıdan gelen soru: onay (ör. Claude Code izin istemi), seçenekli (AskUserQuestion) ya da yanıt beklemeyen
/// karar kartı (`handoff`; Claude masaüstünün karar kutusu, yanıtı Claude'da verilir).
public struct ExternalQuestion: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var detail: String?
    public var symbol: String?
    public var tint: String?
    public var askedAt: Date
    public var expiresAt: Date
    /// Seçenekli soru (İzin ver/Reddet yerine); boşsa onay sorusu.
    public var choices: [String] = []
    public var choiceDetails: [String] = []
    public var allowsMultiple = false
    /// Karar kartı: kimse yanıt beklemez; `choices` yalnız bilgi, düğme soruyu soran uygulamayı açar.
    public var isHandoff = false
    /// Karar kartının özeti.
    public var context: String?
    /// Karar kartının Claude masaüstü oturumu (`local_…`).
    public var session: String?

    public var isChoice: Bool { !choices.isEmpty && !isHandoff }

    public static let maximumDetailLength = 2000
    public static let maximumChoices = 6
    public static let maximumChoiceLength = 120
    public static let maximumChoiceDetailLength = 300
    public static let maximumContextLength = 600
    /// Kanca zaman aşımından (Claude'da varsayılan 600 sn) önce düşsün.
    public static let defaultTTL: TimeInterval = 110
    public static let ttlRange: ClosedRange<TimeInterval> = 1...590
    /// Karar kartı kimseyi bekletmez; kullanıcı masadan uzaktaysa da bir süre görünsün.
    public static let handoffTTLRange: ClosedRange<TimeInterval> = 1...3600

    /// Başlık, alt başlık, simge ve renk etkinlikle aynı kurallarla; ayrıntı ve süre ayrıca.
    public static func validated(from request: ActivityRequest, now: Date = .now)
        throws(ExternalActivity.ValidationError) -> ExternalQuestion {
        let base = try ExternalActivity.validated(from: request, now: now)
        if let detail = request.detail, detail.count > maximumDetailLength {
            throw .invalid("detail", rule: "≤ \(maximumDetailLength)")
        }
        let isHandoff = request.op == .handoff
        let ttl = request.ttl ?? defaultTTL
        if isHandoff {
            guard handoffTTLRange.contains(ttl) else { throw .invalid("ttl", rule: "1…3600 s") }
        } else {
            guard ttlRange.contains(ttl) else { throw .invalid("ttl", rule: "1…590 s") }
        }
        if let context = request.context, context.count > maximumContextLength {
            throw .invalid("context", rule: "≤ \(maximumContextLength)")
        }
        if let session = request.session, !ClaudeStopHook.isDesktopSessionID(session) {
            throw .invalid("session", rule: "local_[A-Za-z0-9-]{1,64}")
        }
        let choices = request.choices ?? []
        let details = request.choiceDetails ?? []
        guard choices.count <= maximumChoices,
              choices.allSatisfy({ !$0.isEmpty && $0.count <= maximumChoiceLength }) else {
            throw .invalid("choices", rule: "≤ \(maximumChoices) × ≤ \(maximumChoiceLength)")
        }
        guard details.isEmpty || details.count == choices.count,
              details.allSatisfy({ $0.count <= maximumChoiceDetailLength }) else {
            throw .invalid("choiceDetails", rule: "= choices, ≤ \(maximumChoiceDetailLength)")
        }
        return ExternalQuestion(id: base.id, title: base.title, subtitle: base.subtitle, detail: request.detail,
                                symbol: base.symbol, tint: base.tint, askedAt: now,
                                expiresAt: now.addingTimeInterval(ttl), choices: choices, choiceDetails: details,
                                allowsMultiple: request.multiple ?? false, isHandoff: isHandoff,
                                context: isHandoff ? request.context : nil, session: isHandoff ? request.session : nil)
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
    /// Tür başına: onay soruları (İzin ver/Reddet) ve seçenekli sorular ayrı açılıp kapanır.
    @ObservationIgnored public var acceptsApprovals = true
    @ObservationIgnored public var acceptsChoices = true
    @ObservationIgnored public var acceptsHandoffs = true

    public func accepts(_ question: ExternalQuestion) -> Bool {
        guard isEnabled else { return false }
        if question.isHandoff { return acceptsHandoffs }
        return question.isChoice ? acceptsChoices : acceptsApprovals
    }
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
        /// Başka bir süreç "başka yerde yanıtlandı" dedi (`dismiss`; ör. Claude'da onaylandı, araç çalıştı).
        case dismissed
    }
    @ObservationIgnored private var waiters: [String: CheckedContinuation<ActivityResponse.Decision?, Never>] = [:]
    @ObservationIgnored private var expiryTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var resolvedEarly: Set<String> = []
    /// Seçenekli yanıt, bekleyen istemci uyandığında okunur.
    @ObservationIgnored private var selections: [String: [Int]] = [:]

    public static let maximumQuestions = 8

    public init() {}

    /// Şu an gösterilen soru: bekleyen istemcisi olan en eski soru, yoksa en eski karar kartı. Kart yarım saat
    /// durabilir; arkasından gelen süreli izin istemini örtmesin.
    public var current: ExternalQuestion? { questions.first { !$0.isHandoff } ?? questions.first }

    public func ask(_ request: ActivityRequest, now: Date = .now) async -> ActivityResponse {
        let isChoice = !(request.choices ?? []).isEmpty
        guard isEnabled, isChoice ? acceptsChoices : acceptsApprovals else { return ActivityResponse(ok: true) }
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
        return ActivityResponse(ok: true, decision: decision, selection: selections.removeValue(forKey: id))
    }

    /// Karar kartı: gösterilir ve hemen döner; aynı id'li eski kart yenisiyle değişir. Kapalıysa hata döner
    /// (kanca "Claude bitti" bildirimine geçer).
    public func handoff(_ request: ActivityRequest, now: Date = .now) -> ActivityResponse {
        guard isEnabled, acceptsHandoffs else {
            return .failure(APILanguage.current.text("karar kartları kapalı", "decision cards are off"))
        }
        let question: ExternalQuestion
        do {
            question = try ExternalQuestion.validated(from: request, now: now)
        } catch {
            return .failure(error.description)
        }
        if questions.contains(where: { $0.id == question.id }) { resolve(question.id, with: nil, reason: .dismissed) }
        guard questions.count < Self.maximumQuestions else { return .failure(APILanguage.current.text("en çok \(Self.maximumQuestions) soru bekleyebilir", "at most \(Self.maximumQuestions) questions can wait")) }
        questions.append(question)
        let id = question.id
        expiryTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, question.expiresAt.timeIntervalSince(now))))
            guard !Task.isCancelled else { return }
            self?.resolve(id, with: nil, reason: .expired)
        }
        onQuestionsChanged?(questions)
        return .success
    }

    /// `dismiss` isteği: `id` tam eşleşir; `*` ile biterse önek. Kapatılan soru sayısı döner, bekleyen
    /// istemci "yanıt yok" alır (Claude zaten karar vermiştir, kanca hiçbir şey yazmaz).
    public func dismiss(_ request: ActivityRequest) -> ActivityResponse {
        guard let pattern = request.id, !pattern.isEmpty, pattern != "*" else {
            return .failure(ExternalActivity.ValidationError.missing("id").description)
        }
        let matches: (String) -> Bool = pattern.hasSuffix("*")
            ? { $0.hasPrefix(String(pattern.dropLast())) } : { $0 == pattern }
        let ids = questions.map(\.id).filter(matches)
        for id in ids { resolve(id, with: nil, reason: .dismissed) }
        return ActivityResponse(ok: true, dismissed: ids.count)
    }

    /// Kullanıcının yanıtı; nil = "kendi akışında yanıtla" (istemci normal yoluna döner).
    public func answer(_ id: String, with decision: ActivityResponse.Decision?) {
        resolve(id, with: decision, reason: .answered)
    }

    /// Seçenekli sorunun yanıtı: seçilen sıralar. Geçersizse (aralık dışı, tek seçimlide birden çok) yok sayılır.
    public func answer(_ id: String, selection: [Int]) {
        guard let question = questions.first(where: { $0.id == id }), question.isChoice,
              !selection.isEmpty, selection.allSatisfy(question.choices.indices.contains),
              question.allowsMultiple || selection.count == 1 else { return }
        selections[id] = Array(Set(selection)).sorted()
        resolve(id, with: nil, reason: .answered)
    }

    private func resolve(_ id: String, with decision: ActivityResponse.Decision?, reason: Resolution) {
        guard let question = questions.first(where: { $0.id == id }) else { return }
        questions.removeAll { $0.id == id }
        onResolved?(question, decision, reason)
        expiryTasks.removeValue(forKey: id)?.cancel()
        if let waiter = waiters.removeValue(forKey: id) {
            waiter.resume(returning: decision)
        } else if !question.isHandoff {
            // Görev iptali beklemeye girilmeden geldiyse: bekleme başlarken hemen çözülsün.
            resolvedEarly.insert(id)
        }
        onQuestionsChanged?(questions)
    }
}
