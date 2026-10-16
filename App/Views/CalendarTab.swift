import Integrations
import NotchShell
import SwiftUI

struct CalendarTab: View {
    let calendar: CalendarMonitor
    /// Ayarlarda kapalıysa nil.
    let reminders: RemindersMonitor?

    var body: some View {
        // Etkinlik de anımsatıcı da yoksa iki boş kutu yerine tek sakin satır.
        if isQuietDay {
            EmptyStateView(symbol: "calendar.badge.checkmark", title: "Bugün boş görünüyor",
                           message: "Önümüzdeki 24 saatte etkinlik ve anımsatıcı yok.")
        } else {
            HStack(alignment: .top, spacing: 10) {
                events
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if let reminders {
                    RemindersColumn(reminders: reminders)
                        .frame(width: 210, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .notchCard()
                }
            }
        }
    }

    private var isQuietDay: Bool {
        guard calendar.access == .granted, calendar.upcoming.isEmpty else { return false }
        guard let reminders else { return true }
        return reminders.access == .granted && reminders.reminders.isEmpty
    }

    /// İzin durumu ve boş/dolu değişince çapraz geçiş.
    private var events: some View {
        ZStack {
            eventsContent
                .id("\(calendar.access)-\(calendar.upcoming.isEmpty)")
                .notchTransition(.swap)
        }
        .notchAnimation(value: "\(calendar.access)-\(calendar.upcoming.isEmpty)")
    }

    @ViewBuilder
    private var eventsContent: some View {
        switch calendar.access {
        case .notDetermined:
            EmptyStateView(symbol: "calendar", title: "Yaklaşan toplantılar",
                           message: "Yaklaşan toplantıları görmek için takvim izni gerekiyor.") {
                Button("Takvime erişim ver") { Task { await calendar.requestAccess() } }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, tint: .blue))
            }
        case .denied:
            EmptyStateView(symbol: "calendar.badge.exclamationmark", title: "Takvim izni kapalı",
                           message: "Gizlilik ayarlarından NotchMVP'ye izin verin.") {
                Button("Gizlilik ayarlarını aç") { CalendarMonitor.openPrivacySettings() }
                    .buttonStyle(CapsuleButtonStyle())
            }
        case .granted:
            if calendar.upcoming.isEmpty {
                EmptyStateView(symbol: "calendar.badge.checkmark", title: "Önümüzdeki 24 saatte etkinlik yok")
            } else {
                // Göreli zaman dakikada bir; görünüm yalnız notch açıkken var.
                TimelineView(.everyMinute) { timeline in
                    VStack(alignment: .leading, spacing: 8) {
                        CardLabel("Yaklaşan")
                        ForEach(calendar.upcoming.prefix(3)) { event in
                            EventRow(event: event, now: timeline.date).notchTransition(.listItem)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .notchCard()
                    .notchAnimation(value: calendar.upcoming.prefix(3).map(\.id))
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarMonitor.Event
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(event.swiftUIColor).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(text: event.title.isEmpty ? String(localized: "Başlıksız etkinlik") : event.title,
                            size: 12, weight: .semibold, trigger: .hover)
                Text(detail)
                    .font(NotchDesign.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let url = event.meetingURL {
                Button("Katıl") { NSWorkspace.shared.open(url) }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, tint: .blue))
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
            CardLabel("Anımsatıcılar")
                .onAppear { reminders.refreshAccess() }
            switch reminders.access {
            case .notDetermined:
                Button("Anımsatıcıları göster") { Task { await reminders.requestAccess() } }
                    .buttonStyle(CapsuleButtonStyle())
            case .denied:
                Button("Gizlilik ayarlarını aç") { RemindersMonitor.openPrivacySettings() }
                    .buttonStyle(CapsuleButtonStyle())
            case .granted:
                if reminders.reminders.isEmpty {
                    Text("Bugün için anımsatıcı yok")
                        .font(NotchDesign.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reminders.reminders.prefix(4)) { reminder in
                        // Tamamlanan anımsatıcı kayarak çıkar.
                        ReminderRow(reminder: reminder, reminders: reminders).notchTransition(.listItem)
                    }
                }
            }
        }
        .notchAnimation(value: reminders.reminders.map(\.id))
        .notchAnimation(value: reminders.access)
    }
}

private struct ReminderRow: View {
    let reminder: RemindersMonitor.Reminder
    let reminders: RemindersMonitor

    var body: some View {
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
            MarqueeText(text: reminder.title.isEmpty ? String(localized: "Başlıksız anımsatıcı") : reminder.title,
                        size: 12, trigger: .hover)
                .foregroundStyle(reminder.isOverdue ? .red : .white)
        }
    }
}
