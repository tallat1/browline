import Foundation
import Observation

/// Dış etkinliklerin durumu. Süresi dolan etkinlik tek bir uyuyan Task ile düşer; boşta yoklama yok.
@MainActor
@Observable
public final class ExternalActivityStore {
    public private(set) var activities: [ExternalActivity] = []
    /// Şu an gösterilen kısa bildirim.
    public private(set) var flash: ExternalActivity?

    @ObservationIgnored public var onActivitiesChanged: (([ExternalActivity]) -> Void)?
    @ObservationIgnored public var onFlash: ((ExternalActivity, Duration) -> Void)?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    public static let maximumActivities = 8

    public init() {}

    public func handle(_ request: ActivityRequest, now: Date = .now) -> ActivityResponse {
        do {
            switch request.op {
            case .ping:
                return .success
            case .list:
                return ActivityResponse(ok: true, activities: activities)
            case .push:
                let activity = try ExternalActivity.validated(from: request, now: now)
                if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                    activities[index] = activity
                } else {
                    guard activities.count < Self.maximumActivities else {
                        return .failure("en çok \(Self.maximumActivities) etkinlik; önce birini bitirin")
                    }
                    activities.append(activity)
                }
                changed()
                return .success
            case .end:
                guard let id = request.id else { return .failure("id gerekli") }
                guard activities.contains(where: { $0.id == id }) else { return .failure("\(id) bulunamadı") }
                activities.removeAll { $0.id == id }
                changed()
                return .success
            case .flash:
                let activity = try ExternalActivity.validated(from: request, now: now, requireID: false)
                let seconds = request.duration ?? 3
                guard ExternalActivity.flashDurationRange.contains(seconds) else {
                    return .failure("duration (0,5…15 sn)")
                }
                flash = activity
                onFlash?(activity, .milliseconds(Int(seconds * 1000)))
                return .success
            }
        } catch {
            return .failure(error.description)
        }
    }

    /// Süre dolanları düşürür; uygulama açıkken kendiliğinden çağrılır, testler doğrudan çağırabilir.
    public func removeExpired(now: Date = .now) {
        let before = activities.count
        activities.removeAll { $0.expiresAt <= now }
        if activities.count != before { changed() }
    }

    private func changed() {
        activities.sort { ($0.priority, $0.updatedAt) > ($1.priority, $1.updatedAt) }
        onActivitiesChanged?(activities)
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let next = activities.map(\.expiresAt).min() else { return }
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 0.05))
            guard let self, !Task.isCancelled else { return }
            self.removeExpired()
        }
    }
}
