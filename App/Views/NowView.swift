import ActivityAPI
import Integrations
import NotchShell
import SwiftUI

/// Şimdi: açılış ekranı. Solda oynatıcı; sağda yalnız o an önemli olanlar (sıradaki toplantı, çalışan
/// zamanlayıcı, canlı etkinlik, Claude limiti), en çok üç kart. Hiçbiri yoksa oynatıcı tüm genişliği
/// alır. Karta basınca ayrıntı sekmesi açılır.
struct NowView: View {
    let coordinator: AppCoordinator
    let model: NotchSurfaceModel

    static let sideWidth: CGFloat = 190

    var body: some View {
        // Toplantı yaklaşınca kart dakikada bir yenilenir; görünüm yalnız notch açıkken var.
        TimelineView(.everyMinute) { timeline in
            let items = NowItem.current(coordinator: coordinator, now: timeline.date)
            HStack(alignment: .top, spacing: 10) {
                if coordinator.settings.nowPlayingEnabled {
                    MediaTab(nowPlaying: coordinator.nowPlaying, volume: coordinator.volume, model: model,
                             sourceDescription: coordinator.nowPlayingSourceDescription)
                }
                if !items.isEmpty {
                    sideColumn(items, now: timeline.date)
                        .frame(maxWidth: coordinator.settings.nowPlayingEnabled ? Self.sideWidth : .infinity)
                        .notchTransition(.fade)
                } else if !coordinator.settings.nowPlayingEnabled {
                    EmptyStateView(symbol: "checkmark.circle", title: "Şu an bekleyen bir şey yok")
                }
            }
            .notchAnimation(value: items.map(\.id))
        }
    }

    private func sideColumn(_ items: [NowItem], now: Date) -> some View {
        VStack(spacing: 5) {
            ForEach(items) { item in
                card(for: item, now: now).notchTransition(.listItem)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func card(for item: NowItem, now: Date) -> some View {
        switch item {
        case let .meeting(event):
            NowCard(open: open(.calendar)) { MeetingCardContent(event: event, now: now) }
        case .timer:
            NowCard(open: open(.timer)) { TimerCardContent(coordinator: coordinator) }
        case let .activity(activity):
            NowCard(open: open(.activities)) { ActivityCardContent(activity: activity) }
        case .claude:
            NowCard(open: open(.claude)) { ClaudeCardContent(usage: coordinator.claudeUsage) }
        }
    }

    /// Ayrıntı sekmesi kapalı ya da gizliyse kart yalnız bilgi verir.
    private func open(_ tab: NotchTab) -> (() -> Void)? {
        guard coordinator.availableTabs.contains(tab) else { return nil }
        return { coordinator.ui.selectedTab = tab }
    }
}

/// Şimdi'nin sağ sütunundaki öğeler, öncelik sırasıyla.
enum NowItem: Identifiable {
    case meeting(CalendarMonitor.Event)
    case timer
    case activity(ExternalActivity)
    case claude

    var id: String {
        switch self {
        case let .meeting(event): "meeting-\(event.id)"
        case .timer: "timer"
        case let .activity(activity): "activity-\(activity.id)"
        case .claude: "claude"
        }
    }

    static let limit = 3
    /// Toplantı kartı en erken bu kadar önce görünür.
    static let meetingLead: TimeInterval = 4 * 3600

    @MainActor
    static func current(coordinator: AppCoordinator, now: Date) -> [NowItem] {
        var items: [NowItem] = []
        let settings = coordinator.settings
        if settings.calendarEnabled,
           let event = coordinator.calendar.upcoming.first(where: { !$0.isAllDay && $0.end > now }),
           event.start.timeIntervalSince(now) <= meetingLead {
            items.append(.meeting(event))
        }
        if settings.timerEnabled, coordinator.timer.isRunning { items.append(.timer) }
        if settings.activityAPIEnabled {
            items += coordinator.externalActivities.activities.prefix(2).map(NowItem.activity)
        }
        if settings.claudeUsageEnabled, coordinator.claudeUsage.usage?.fiveHour != nil { items.append(.claude) }
        return Array(items.prefix(limit))
    }
}

/// Şimdi kartı: ince dolgu, üzerine gelince aydınlanır, basınca ayrıntıya gider.
private struct NowCard<Content: View>: View {
    let open: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var isHovering = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovering && open != nil ? NotchDesign.cardHoverFill : NotchDesign.cardFill))
            .contentShape(Rectangle())
            .onTapGesture { open?() }
            .onHover { isHovering = $0 }
            .notchAnimation(NotchMotion.hover, value: isHovering)
    }
}

private struct MeetingCardContent: View {
    let event: CalendarMonitor.Event
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(event.swiftUIColor).frame(width: 6, height: 6)
                Text(relative).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if let url = event.meetingURL {
                    Button("Katıl") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.plain)
                        .font(NotchDesign.captionEmphasized)
                        .foregroundStyle(.blue)
                }
            }
            MarqueeText(text: event.title.isEmpty ? String(localized: "Başlıksız etkinlik") : event.title,
                        size: 12, weight: .semibold, trigger: .hover)
        }
    }

    private var relative: String {
        if event.start <= now { return String(localized: "sürüyor") }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return String(localized: "\(minutes) dk sonra") }
        return String(localized: "\(minutes / 60) sa \(minutes % 60) dk sonra")
    }
}

private struct TimerCardContent: View {
    let coordinator: AppCoordinator

    var body: some View {
        // Saniyelik çizim yalnız bu kartta.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let timer = coordinator.timer
            let phase = coordinator.ui.pomodoroPhase
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(phase?.title ?? String(localized: "Zamanlayıcı"))
                        .font(NotchDesign.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(CountdownTimer.format(timer.remaining(at: timeline.date)))
                        .font(NotchDesign.bodyEmphasized.monospacedDigit())
                    Button { coordinator.cancelTimer() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(IconButtonStyle(size: 18))
                    .help("İptal")
                }
                ThinBar(fraction: timer.progress(at: timeline.date), tint: phase?.tint ?? .orange)
            }
        }
    }
}

private struct ActivityCardContent: View {
    let activity: ExternalActivity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: activity.title, size: 12, weight: .semibold, trigger: .hover)
                if let progress = activity.progress {
                    ThinBar(fraction: progress, tint: activity.tintColor)
                } else if let subtitle = activity.subtitle {
                    Text(subtitle).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

private struct ClaudeCardContent: View {
    let usage: ClaudeUsageMonitor

    var body: some View {
        let session = usage.usage?.fiveHour?.usedPercentage ?? 0
        let week = usage.usage?.sevenDay?.usedPercentage
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                Text("Claude").font(NotchDesign.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(summary(session: session, week: week))
                    .font(NotchDesign.captionEmphasized.monospacedDigit())
                    .lineLimit(1)
            }
            ThinBar(fraction: session / 100, tint: session >= 80 ? .orange : Color(red: 0.85, green: 0.47, blue: 0.34))
        }
    }

    private func summary(session: Double, week: Double?) -> String {
        let sessionText = NowFormat.percent(session)
        guard let week else { return sessionText }
        return String(localized: "\(sessionText) · hafta \(NowFormat.percent(week))")
    }
}

/// İnce ilerleme çubuğu (macOS ProgressView .tint'i yok sayıyor).
private struct ThinBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(NotchDesign.track)
                Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 3)
    }
}

enum NowFormat {
    /// 0–100 yüzde, yerele göre ("%22" Türkçe, "22%" İngilizce).
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
