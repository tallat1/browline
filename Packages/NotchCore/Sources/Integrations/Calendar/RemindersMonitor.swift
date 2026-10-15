import AppKit
import EventKit
import Observation

/// Bugüne kadar vadesi gelen tamamlanmamış anımsatıcılar; notch'tan tamamlanabilir. İzin yalnız
/// kullanıcı düğmeye basınca istenir. Değişiklikler EKEventStoreChanged ile gelir, yoklama yok.
@MainActor
@Observable
public final class RemindersMonitor {
    public enum Access: Equatable, Sendable {
        case notDetermined, granted, denied
    }

    public struct Reminder: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let dueDate: Date?
        public let isOverdue: Bool
        /// Listenin rengi (sRGB).
        public let color: [Double]
    }

    public private(set) var access: Access
    public private(set) var reminders: [Reminder] = []
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var changeToken: NSObjectProtocol?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var generation = 0

    public static let maximumItems = 5

    public init() {
        access = Self.currentAccess()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        access = Self.currentAccess()
        guard access == .granted else { return }
        changeToken = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    public func stop() {
        isRunning = false
        generation += 1
        if let changeToken { NotificationCenter.default.removeObserver(changeToken) }
        changeToken = nil
        reminders = []
    }

    public func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            Log.integrations.error("Anımsatıcı izni istenemedi: \(error.localizedDescription, privacy: .public)")
        }
        access = Self.currentAccess()
        Log.integrations.notice("Anımsatıcı izni: \(String(describing: self.access), privacy: .public)")
        if access == .granted, isRunning {
            isRunning = false
            start()
        }
    }

    /// İzin istemi ajan uygulamada yanıt beklemeden dönebiliyor (2026-10-16: iki istek
    /// `notDetermined` döndü, izin sonra verildi). Sütun her göründüğünde yeniden okunur.
    public func refreshAccess() {
        let current = Self.currentAccess()
        guard current != access else { return }
        access = current
        Log.integrations.notice("Anımsatıcı izni değişti: \(String(describing: current), privacy: .public)")
        if current == .granted, isRunning {
            isRunning = false
            start()
        }
    }

    /// Tamamlandı işaretler; liste EKEventStoreChanged ile tazelenir.
    public func complete(_ reminder: Reminder) {
        guard let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        do {
            try store.save(item, commit: true)
            reminders.removeAll { $0.id == reminder.id }
        } catch {
            Log.integrations.error("Anımsatıcı kaydedilemedi: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private func reload() {
        generation += 1
        let current = generation
        let endOfToday = Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 60 * 60)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday,
                                                              calendars: nil)
        // Tamamlama bloğu arka planda; EKReminder Sendable değil, değer tipine orada çevrilir.
        store.fetchReminders(matching: predicate) { items in
            let now = Date.now
            let mapped = (items ?? [])
                .map { item -> Reminder in
                    let due = item.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    let color = item.calendar.map { calendar -> [Double] in
                        guard let rgb = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.sRGB) else { return [] }
                        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map(Double.init)
                    } ?? []
                    return Reminder(id: item.calendarItemIdentifier, title: item.title ?? "", dueDate: due,
                                    isOverdue: due.map { $0 < Calendar.current.startOfDay(for: now) } ?? false,
                                    color: color)
                }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            let limited = Array(mapped.prefix(RemindersMonitor.maximumItems))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, self.generation == current else { return }
                    self.reminders = limited
                    Log.integrations.notice("Anımsatıcılar: \(limited.count) vadesi gelen")
                }
            }
        }
    }
}
