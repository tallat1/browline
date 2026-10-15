import Integrations
import SwiftUI

struct CalendarTab: View {
    let calendar: CalendarMonitor
    /// Ayarlarda kapalıysa nil.
    let reminders: RemindersMonitor?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            events
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let reminders {
                Divider().overlay(Color.white.opacity(0.12))
                RemindersColumn(reminders: reminders)
                    .frame(width: 180, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var events: some View {
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

/// Bugün ve gecikmiş anımsatıcılar; daireye basınca tamamlanır.
private struct RemindersColumn: View {
    let reminders: RemindersMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Anımsatıcılar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .onAppear { reminders.refreshAccess() }
            switch reminders.access {
            case .notDetermined:
                Button("Anımsatıcıları göster") { Task { await reminders.requestAccess() } }
                    .controlSize(.small)
            case .denied:
                Button("Gizlilik ayarlarını aç") { RemindersMonitor.openPrivacySettings() }
                    .controlSize(.small)
            case .granted:
                if reminders.reminders.isEmpty {
                    Text("Bugün için anımsatıcı yok")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reminders.reminders.prefix(4)) { reminder in
                        HStack(spacing: 6) {
                            Button { reminders.complete(reminder) } label: {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color(.sRGB, red: reminder.color[safe: 0] ?? 0.6,
                                                           green: reminder.color[safe: 1] ?? 0.6,
                                                           blue: reminder.color[safe: 2] ?? 0.6))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Tamamlandı olarak işaretle")
                            (reminder.title.isEmpty ? Text("Başlıksız anımsatıcı") : Text(verbatim: reminder.title))
                                .font(.system(size: 11))
                                .foregroundStyle(reminder.isOverdue ? .red : .white)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}
