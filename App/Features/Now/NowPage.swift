import ActivityAPI
import Integrations
import NotchShell
import SwiftUI

/// Şimdi: açılış ekranı. Solda oynatıcı; sağda yalnız o an önemli olanlar (sıradaki toplantı, çalışan
/// zamanlayıcı, canlı etkinlik, Claude limiti), en çok üç kart. Hiçbiri yoksa oynatıcı tüm genişliği
/// alır. Karta basınca ayrıntı sekmesi açılır.
struct NowPage: View {
    let coordinator: AppCoordinator
    let model: NotchSurfaceModel

    static let sideWidth: CGFloat = 190

    var body: some View {
        // Toplantı yaklaşınca kart dakikada bir yenilenir; görünüm yalnız notch açıkken var.
        TimelineView(.everyMinute) { timeline in
            let items = NowItem.current(coordinator: coordinator, now: timeline.currentDate)
            HStack(alignment: .top, spacing: 10) {
                if coordinator.settings.nowPlayingEnabled {
                    MediaPage(nowPlaying: coordinator.nowPlaying, volume: coordinator.volume, model: model,
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
    private func open(_ page: NotchPage) -> (() -> Void)? {
        guard coordinator.availablePages.contains(page) else { return nil }
        return { coordinator.ui.selectedPage = page }
    }
}
