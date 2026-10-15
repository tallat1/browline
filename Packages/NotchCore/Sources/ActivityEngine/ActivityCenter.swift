import Foundation
import Observation

public struct ActivityID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
}

/// Kompakt notch'ta gösterilebilecek bir etkinlik. Görünümü uygulama kimliğe göre seçer.
public struct Activity: Equatable, Sendable, Identifiable {
    public let id: ActivityID
    public var priority: Int

    public init(id: ActivityID, priority: Int) {
        self.id = id
        self.priority = priority
    }
}

/// Hangi etkinliğin öne çıkacağına karar verir.
/// Canlı etkinlikler (çalan müzik, yaklaşan toplantı) kaldırılana kadar durur; en yüksek öncelikli
/// olan görünür. Geçici etkinlik (şarj bağlandı) süresi boyunca hepsinin önüne geçer, bitince
/// kaldığı yerden devam edilir. ActivityKit'e benzer fikir; clean-room yazıldı.
@MainActor
@Observable
public final class ActivityCenter {
    public private(set) var current: Activity?
    /// Öne çıkan etkinlik değişince (görünür notch'ların kanatlanması bu bilgiye bağlı).
    @ObservationIgnored public var onCurrentChanged: ((Activity?) -> Void)?
    /// Herhangi bir canlı ya da geçici etkinlik değişince; öne çıkan aynı kalsa bile. Kısıtlı
    /// yüzeyler (kilit ekranı) arkada kalan etkinliği gösterebildiği için buna ihtiyaç duyar.
    @ObservationIgnored public var onActivitiesChanged: (() -> Void)?

    private var live: [ActivityID: Activity] = [:]
    private var transient: Activity?
    @ObservationIgnored private var transientTask: Task<Void, Never>?

    public init() {}

    /// Öncelik sırasıyla canlı etkinlikler (eşit öncelikte kimliğe göre, kararlı sıra için).
    public var liveActivities: [Activity] {
        live.values.sorted { ($0.priority, $1.id.rawValue) > ($1.priority, $0.id.rawValue) }
    }

    public func isLive(_ id: ActivityID) -> Bool { live[id] != nil }

    /// Yalnız izin verilen kimlikler arasında öne çıkan; kilit ekranı gibi kısıtlı yüzeyler için.
    /// İzinsiz bir kısa bildirim izinli canlı etkinliği gizlemez.
    public func current(allowing isAllowed: (ActivityID) -> Bool) -> Activity? {
        if let transient, isAllowed(transient.id) { return transient }
        return liveActivities.first { isAllowed($0.id) }
    }

    public func setLive(_ id: ActivityID, priority: Int) {
        let activity = Activity(id: id, priority: priority)
        guard live[id] != activity else { return }
        live[id] = activity
        recompute()
    }

    public func removeLive(_ id: ActivityID) {
        guard live.removeValue(forKey: id) != nil else { return }
        recompute()
    }

    /// Geçici etkinlik. Yeni bir flash öncekinin yerini alır.
    public func flash(_ id: ActivityID, priority: Int = 1_000, duration: Duration) {
        transientTask?.cancel()
        transient = Activity(id: id, priority: priority)
        recompute()
        transientTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            self.transient = nil
            self.recompute()
        }
    }

    public func cancelFlash(_ id: ActivityID) {
        guard transient?.id == id else { return }
        transientTask?.cancel()
        transient = nil
        recompute()
    }

    private func recompute() {
        let next = transient ?? liveActivities.first
        if next != current {
            current = next
            onCurrentChanged?(next)
        }
        onActivitiesChanged?()
    }
}
