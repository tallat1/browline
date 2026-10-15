import AppKit
import EventKit
import Observation

/// Yaklaşan etkinlikler (EventKit, macOS 14 tam erişim). İzin yalnız kullanıcı istediğinde istenir.
/// Değişiklik EKEventStoreChanged ile, "toplantı yaklaşıyor" geçişi tek seferlik uykuyla gelir;
/// sürekli yoklama yok.
@MainActor
@Observable
public final class CalendarMonitor {
    public enum Access: Equatable, Sendable {
        case notDetermined
        case granted
        case denied
    }

    public struct Event: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let start: Date
        public let end: Date
        public let isAllDay: Bool
        public let meetingURL: URL?
        /// Takvimin rengi, sRGB bileşenleri.
        public let color: [Double]
    }

    public private(set) var access: Access
    public private(set) var upcoming: [Event] = []
    /// 10 dakika içinde başlayacak ya da sürmekte olan, bağlantılı toplantı.
    public private(set) var imminentMeeting: Event?
    @ObservationIgnored public var onImminentMeetingChanged: ((Event?) -> Void)?

    public static let imminentLead: TimeInterval = 10 * 60

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var changeToken: NSObjectProtocol?
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false

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
        if let changeToken { NotificationCenter.default.removeObserver(changeToken) }
        changeToken = nil
        boundaryTask?.cancel()
        upcoming = []
        setImminent(nil)
    }

    /// Sistem izin istemini gösterir. Reddedildiyse Sistem Ayarları'na yönlendirmek gerekir.
    public func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            Log.integrations.error("Takvim izni istenemedi: \(error.localizedDescription, privacy: .public)")
        }
        access = Self.currentAccess()
        Log.integrations.notice("Takvim izni: \(String(describing: self.access), privacy: .public)")
        if access == .granted, isRunning {
            isRunning = false
            start()
        }
    }

    public static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private func reload() {
        let now = Date.now
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-4 * 60 * 60),
                                                 end: horizon, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)
            .map(Self.makeEvent)
        upcoming = Array(events)
        // Başlık kişisel; günlüğe yalnız sayı yazılır.
        Log.integrations.notice("Takvim: \(self.upcoming.count) yaklaşan etkinlik, bağlantılı \(self.upcoming.filter { $0.meetingURL != nil }.count)")
        refreshImminent()
    }

    private static func makeEvent(_ event: EKEvent) -> Event {
        let color = event.calendar?.color?.usingColorSpace(.sRGB)
        return Event(
            id: event.calendarItemIdentifier + "|" + String(event.startDate.timeIntervalSince1970),
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            meetingURL: MeetingLink.find(url: event.url, location: event.location, notes: event.notes),
            color: color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent] } ?? [0.5, 0.5, 0.5])
    }

    /// Bir sonraki sınırda (bir toplantının 10 dk öncesi, başlangıcı ya da bitişi) tek bir uyanma.
    private func refreshImminent() {
        let now = Date.now
        let meetings = upcoming.filter { !$0.isAllDay && $0.meetingURL != nil }
        setImminent(meetings.first { $0.start.addingTimeInterval(-Self.imminentLead) <= now && $0.end > now })

        let boundaries = meetings.flatMap { [$0.start.addingTimeInterval(-Self.imminentLead), $0.end] }
            .filter { $0 > now }
        boundaryTask?.cancel()
        guard let next = boundaries.min() else { return }
        boundaryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSince(now) + 1))
            guard let self, !Task.isCancelled else { return }
            self.reload()
        }
    }

    private func setImminent(_ event: Event?) {
        guard event != imminentMeeting else { return }
        imminentMeeting = event
        Log.integrations.notice("Takvim: yaklaşan toplantı \(event == nil ? "yok" : "var", privacy: .public)")
        onImminentMeetingChanged?(event)
    }
}
