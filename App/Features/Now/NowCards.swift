import ActivityAPI
import Integrations
import NotchShell
import SwiftUI

/// Şimdi kartı: ince dolgu, üzerine gelince aydınlanır, basınca ayrıntıya gider.
struct NowCard<Content: View>: View {
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

struct MeetingCardContent: View {
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

struct TimerCardContent: View {
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

struct ActivityCardContent: View {
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

struct ClaudeCardContent: View {
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
struct CallCardContent: View {
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
struct CICardContent: View {
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
