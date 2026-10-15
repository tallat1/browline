import Foundation
import Observation

/// Geri sayım. Tek bir uyuyan Task bitişi bekler; saniyelik tik yok, kalan süreyi görünüm
/// yalnız ekrandayken kendisi hesaplar.
@MainActor
@Observable
public final class CountdownTimer {
    public private(set) var endsAt: Date?
    public private(set) var duration: TimeInterval = 0
    @ObservationIgnored public var onRunningChanged: ((Bool) -> Void)?
    @ObservationIgnored public var onFinished: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    public static let maximumDuration: TimeInterval = 24 * 60 * 60

    public init() {}

    public var isRunning: Bool { endsAt != nil }

    public func start(seconds: TimeInterval, now: Date = .now) {
        let seconds = min(max(seconds, 1), Self.maximumDuration)
        duration = seconds
        schedule(until: now.addingTimeInterval(seconds))
        Log.integrations.notice("Zamanlayıcı başladı: \(Int(seconds)) sn")
        onRunningChanged?(true)
    }

    /// Çalışan zamanlayıcıya süre ekler (toplam süre de büyür, ilerleme halkası geri gitmez).
    public func add(seconds: TimeInterval, now: Date = .now) {
        guard let endsAt else { return start(seconds: seconds, now: now) }
        let newEnd = min(endsAt.addingTimeInterval(seconds), now.addingTimeInterval(Self.maximumDuration))
        duration += newEnd.timeIntervalSince(endsAt)
        schedule(until: newEnd)
    }

    public func cancel() {
        task?.cancel()
        task = nil
        guard endsAt != nil else { return }
        endsAt = nil
        Log.integrations.notice("Zamanlayıcı iptal edildi")
        onRunningChanged?(false)
    }

    public func remaining(at now: Date) -> TimeInterval {
        endsAt.map { max(0, $0.timeIntervalSince(now)) } ?? 0
    }

    /// 0…1, geçen süre oranı.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    /// 65 → "1:05", 3725 → "1:02:05". Kalan süre yukarı yuvarlanır: "0:00" yalnız bittiğinde görünür.
    public nonisolated static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                         : String(format: "%d:%02d", minutes, secs)
    }

    private func schedule(until end: Date) {
        endsAt = end
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard let self, !Task.isCancelled, self.endsAt == end else { return }
            self.endsAt = nil
            self.task = nil
            Log.integrations.notice("Zamanlayıcı bitti")
            self.onRunningChanged?(false)
            self.onFinished?()
        }
    }
}
