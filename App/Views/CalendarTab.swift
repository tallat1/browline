import Integrations
import SwiftUI

struct CalendarTab: View {
    let calendar: CalendarMonitor

    var body: some View {
        switch calendar.access {
        case .notDetermined:
            permissionPrompt(
                text: "Yaklaşan toplantıları görmek için takvim izni gerekiyor.",
                button: "Takvime erişim ver") {
                    Task { await calendar.requestAccess() }
                }
        case .denied:
            permissionPrompt(
                text: "Takvim izni kapalı. Gizlilik ayarlarından NotchMVP'ye izin verin.",
                button: "Gizlilik ayarlarını aç") {
                    CalendarMonitor.openPrivacySettings()
                }
        case .granted:
            if calendar.upcoming.isEmpty {
                Text("Önümüzdeki 24 saatte etkinlik yok")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Göreli zaman dakikada bir; görünüm yalnız notch açıkken var.
                TimelineView(.everyMinute) { timeline in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(calendar.upcoming.prefix(3)) { event in
                            EventRow(event: event, now: timeline.date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func permissionPrompt(text: LocalizedStringKey, button: LocalizedStringKey,
                                  action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(button, action: action)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventRow: View {
    let event: CalendarMonitor.Event
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(event.swiftUIColor).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                (event.title.isEmpty ? Text("Başlıksız etkinlik") : Text(verbatim: event.title))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let url = event.meetingURL {
                Button("Katıl") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var detail: String {
        if event.isAllDay { return String(localized: "Tüm gün") }
        let time = event.start.formatted(date: .omitted, time: .shortened) + "–"
            + event.end.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInTomorrow(event.start) ? String(localized: "Yarın") + " " : ""
        return day + time + " · " + relative
    }

    private var relative: String {
        if event.start <= now { return String(localized: "sürüyor") }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return String(localized: "\(minutes) dk sonra") }
        let hours = minutes / 60
        return String(localized: "\(hours) sa \(minutes % 60) dk sonra")
    }
}
