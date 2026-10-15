import Integrations
import SwiftUI

/// Claude plan limitleri: 5 saatlik oturum ve haftalık pencere. Veri Claude Code durum satırından
/// gelir; yalnız bir oturum çalışırken tazelendiği için son güncelleme zamanı da gösterilir.
struct ClaudeTab: View {
    let usage: ClaudeUsageMonitor

    var body: some View {
        if let current = usage.usage {
            TimelineView(.everyMinute) { timeline in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        WindowCard(title: "Oturum (5 saat)", window: current.fiveHour, now: timeline.date, relative: true)
                        WindowCard(title: "Haftalık", window: current.sevenDay, now: timeline.date, relative: false)
                    }
                    Text(updatedText(current.capturedAt, now: timeline.date))
                        .font(NotchDesign.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if usage.statuslineSeenAt != nil {
            // Betik çalışıyor ama limit gelmiyor: hesap Pro/Max değil ya da oturumda henüz yanıt yok.
            EmptyStateView(symbol: "sparkles", title: "Durum satırı çalışıyor, limit gelmedi",
                           message: "Claude yalnız Pro ve Max aboneliklerinde, oturumdaki ilk yanıttan sonra limit bildirir.")
                .onAppear { usage.refreshSeen() }
        } else {
            EmptyStateView(symbol: "sparkles", title: "Henüz limit verisi yok",
                           message: "Claude Code durum satırı kurulunca 5 saatlik ve haftalık limitler burada görünür.")
                .onAppear { usage.refreshSeen() }
        }
    }

    private func updatedText(_ captured: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(captured) / 60)
        if minutes < 1 { return String(localized: "Az önce güncellendi") }
        if minutes < 60 { return String(localized: "\(minutes) dk önce güncellendi · Claude Code oturumu açıkken tazelenir") }
        return String(localized: "\(minutes / 60) sa önce güncellendi · Claude Code oturumu açıkken tazelenir")
    }
}

private struct WindowCard: View {
    let title: LocalizedStringKey
    let window: ClaudeUsageMonitor.Window?
    let now: Date
    let relative: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(title)
            if let window {
                let percent = Int(window.usedPercentage.rounded())
                Text(verbatim: "%\(percent)").font(.system(size: 22, weight: .semibold).monospacedDigit())
                LevelBar(level: window.usedPercentage / 100, tint: tint(for: window.usedPercentage)).frame(height: 5)
                if let reset = window.resetsAt, reset > now {
                    Text(resetText(reset)).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Veri yok").font(NotchDesign.body).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }

    private func tint(for percent: Double) -> Color {
        percent >= 90 ? .red : (percent >= 75 ? .orange : Color(red: 0.85, green: 0.47, blue: 0.34))
    }

    private func resetText(_ reset: Date) -> String {
        if relative {
            let minutes = Int((reset.timeIntervalSince(now) / 60).rounded(.up))
            return minutes < 60
                ? String(localized: "\(minutes) dk sonra sıfırlanır")
                : String(localized: "\(minutes / 60) sa \(minutes % 60) dk sonra sıfırlanır")
        }
        return String(localized: "\(reset.formatted(.dateTime.weekday(.wide).hour().minute())) sıfırlanır")
    }
}
