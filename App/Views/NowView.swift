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
            let items = NowItem.current(coordinator: coordinator, now: timeline.currentDate)
            HStack(alignment: .top, spacing: 10) {
                if coordinator.settings.nowPlayingEnabled {
                    MediaTab(nowPlaying: coordinator.nowPlaying, volume: coordinator.volume, model: model,
                             sourceDescription: coordinator.nowPlayingSourceDescription)
                }
                if !items.isEmpty {
                    sideColumn(items, now: timeline.currentDate)
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
        case let .activity(activity, more):
            NowCard(open: open(.activities)) { ActivityCardContent(activity: activity, more: more) }
        case .claude:
            NowCard(open: open(.claude)) { ClaudeCardContent(usage: coordinator.claudeUsage) }
        case .call:
            NowCard(open: nil) { CallCardContent(microphone: coordinator.microphone) }
        case let .ci(run):
            NowCard(open: open(.ci)) { CICardContent(run: run, others: coordinator.ci.activeRuns.count - 1) }
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
        // Mikrofon kullanımdaysa (görüşme) ya da sessizdeyse en üstte.
        if settings.meetingControlsEnabled, coordinator.microphone.canMute,
           coordinator.privacy.isMicrophoneActive || coordinator.microphone.isMuted {
            items.append(.call)
        }
        if settings.calendarEnabled,
           let event = coordinator.calendar.upcoming.first(where: { !$0.isAllDay && $0.end > now }),
           event.start.timeIntervalSince(now) <= meetingLead {
            items.append(.meeting(event))
        }
        if settings.timerEnabled, coordinator.timer.isRunning { items.append(.timer) }
        if settings.ciEnabled, let run = coordinator.ci.activeRuns.first { items.append(.ci(run)) }
        if settings.activityAPIEnabled {
            items += coordinator.externalActivities.activities.prefix(2).map { NowItem.activity($0) }
        }
        if settings.claudeUsageEnabled, coordinator.claudeUsage.usage?.fiveHour != nil { items.append(.claude) }
        var shown = Array(items.prefix(limit))
        // Etkinlikler sekmesi Şimdi'ye katıldı: sığmayanlar son etkinlik kartında sayı olarak.
        let total = settings.activityAPIEnabled ? coordinator.externalActivities.activities.count : 0
        let activityIndices = shown.indices.filter { if case .activity = shown[$0] { true } else { false } }
        if let last = activityIndices.last, total > activityIndices.count,
           case let .activity(activity, _) = shown[last] {
            shown[last] = .activity(activity, more: total - activityIndices.count)
        }
        return shown
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
            .background(RoundedRectangle(cornerRadius: NotchDesign.Radius.medium, style: .continuous)
                .fill(isHovering && open != nil ? NotchDesign.cardHoverFill : NotchDesign.cardFill))
            .overlay(RoundedRectangle(cornerRadius: NotchDesign.Radius.medium, style: .continuous)
                .strokeBorder(NotchDesign.hairline, lineWidth: 0.5))
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
                    Text(CountdownTimer.format(timer.remaining(at: timeline.currentDate)))
                        .font(NotchDesign.bodyEmphasized.monospacedDigit())
                    Button { coordinator.cancelTimer() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(IconButtonStyle(size: 18))
                    .help("İptal")
                }
                ThinBar(fraction: timer.progress(at: timeline.currentDate), tint: phase?.tint ?? .orange)
            }
        }
    }
}

private struct ActivityCardContent: View {
    let activity: ExternalActivity
    var more = 0

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
            if more > 0 {
                Spacer(minLength: 4)
                Text(verbatim: "+\(more)")
                    .font(NotchDesign.captionEmphasized)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(NotchDesign.selectionFill))
                    .help("Tüm etkinlikler")
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

/// Görüşme: mikrofonu kullanan uygulama, sessize alma ve uygulamaya dönüş.
private struct CallCardContent: View {
    let microphone: MicrophoneControl

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: microphone.inputApps.first?.name ?? String(localized: "Mikrofon"))
                    .font(NotchDesign.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(microphone.isMuted ? "Sessizde" : "Mikrofon açık")
                    .font(NotchDesign.bodyEmphasized)
                    .foregroundStyle(microphone.isMuted ? .red : .primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !microphone.inputApps.isEmpty {
                Button(action: microphone.activateInputApp) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: NotchDesign.Icon.small, weight: NotchDesign.Icon.weight))
                }
                .buttonStyle(IconButtonStyle(size: NotchDesign.Control.small))
                .help("Görüşmeye dön")
            }
            Button(action: microphone.toggleMute) {
                Image(systemName: microphone.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(microphone.isMuted ? .white : .primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(microphone.isMuted ? Color.red : NotchDesign.selectionFill))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .help(microphone.isMuted ? "Mikrofonu aç" : "Mikrofonu sessize al (tüm uygulamalar)")
        }
        .notchAnimation(value: microphone.isMuted)
    }
}

/// Süren derleme: depo · iş akışı, commit başlığı ve geçen süre.
private struct CICardContent: View {
    let run: CIMonitor.Run
    let others: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: run.workflow.isEmpty ? run.repositoryName : "\(run.repositoryName) · \(run.workflow)",
                            size: 12, weight: .semibold, trigger: .hover)
                Text(verbatim: run.title).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(CountdownTimer.format(max(0, timeline.date.timeIntervalSince(run.createdAt))))
                        .font(NotchDesign.captionEmphasized.monospacedDigit())
                        .foregroundStyle(.orange)
                }
                if others > 0 {
                    Text(verbatim: "+\(others)").font(NotchDesign.caption).foregroundStyle(.secondary)
                }
            }
        }
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
