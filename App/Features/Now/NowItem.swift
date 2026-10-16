import ActivityAPI
import Integrations
import NotchShell
import SwiftUI

/// Şimdi'nin sağ sütunundaki öğeler, öncelik sırasıyla.
enum NowItem: Identifiable {
    case meeting(CalendarMonitor.Event)
    case timer
    /// `more`: kartlara sığmayan etkinlik sayısı (son etkinlik kartında "+N"; basınca tümü).
    case activity(ExternalActivity, more: Int = 0)
    case claude
    case call
    /// Süren CI çalışması (ilki).
    case ci(CIMonitor.Run)

    var id: String {
        switch self {
        case let .meeting(event): "meeting-\(event.id)"
        case .timer: "timer"
        case let .activity(activity, _): "activity-\(activity.id)"
        case .claude: "claude"
        case .call: "call"
        case let .ci(run): "ci-\(run.id)"
        }
    }

    static let limit = 3
    /// Toplantı kartı en erken bu kadar önce görünür.
    static let meetingLead: TimeInterval = 4 * 3600

    @MainActor
    static func current(coordinator: AppCoordinator, now: Date) -> [NowItem] {
        var items: [NowItem] = []
        let settings = coordinator.settings
        #if DEBUG
        let isDemo = coordinator.ui.isDemoMode
        #else
        let isDemo = false
        #endif
        let activities = coordinator.externalActivities.activities.filter { !isDemo || $0.id.hasPrefix("demo.") }
        // Mikrofon kullanımdaysa (görüşme) ya da sessizdeyse en üstte.
        if !isDemo, settings.meetingControlsEnabled, coordinator.microphone.canMute,
           coordinator.privacy.isMicrophoneActive || coordinator.microphone.isMuted {
            items.append(.call)
        }
        if !isDemo, settings.calendarEnabled,
           let event = coordinator.calendar.upcoming.first(where: { !$0.isAllDay && $0.end > now }),
           event.start.timeIntervalSince(now) <= meetingLead {
            items.append(.meeting(event))
        }
        if settings.timerEnabled, coordinator.timer.isRunning { items.append(.timer) }
        if !isDemo, settings.ciEnabled, let run = coordinator.ci.activeRuns.first { items.append(.ci(run)) }
        if settings.activityAPIEnabled {
            items += activities.prefix(2).map { NowItem.activity($0) }
        }
        if !isDemo, settings.claudeUsageEnabled, coordinator.claudeUsage.usage?.fiveHour != nil { items.append(.claude) }
        var shown = Array(items.prefix(limit))
        // Etkinlikler sekmesi Şimdi'ye katıldı: sığmayanlar son etkinlik kartında sayı olarak.
        let total = settings.activityAPIEnabled ? activities.count : 0
        let activityIndices = shown.indices.filter { if case .activity = shown[$0] { true } else { false } }
        if let last = activityIndices.last, total > activityIndices.count,
           case let .activity(activity, _) = shown[last] {
            shown[last] = .activity(activity, more: total - activityIndices.count)
        }
        return shown
    }
}
