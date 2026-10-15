import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

/// Bir ekranın notch içeriği: kabuk (şekil, animasyon, hover) NotchShell'den, içerik buradan.
struct NotchRootView: View {
    let model: NotchSurfaceModel
    let coordinator: AppCoordinator

    var body: some View {
        NotchSurfaceView(model: model) {
            CompactLeadingView(coordinator: coordinator)
        } compactTrailing: {
            CompactTrailingView(coordinator: coordinator)
        } expanded: { context in
            ExpandedView(context: context, model: model, coordinator: coordinator)
        }
    }
}

/// Çentiğin solundaki kanat: etkinliğin simgesi ya da kapağı.
struct CompactLeadingView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Group {
            switch coordinator.activities.current?.id {
            case AppCoordinator.ActivityKind.nowPlaying:
                if let artwork = coordinator.nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                }
            case AppCoordinator.ActivityKind.meeting:
                Image(systemName: "video.fill")
                    .foregroundStyle(coordinator.calendar.imminentMeeting.map(\.swiftUIColor) ?? .white)
            case AppCoordinator.ActivityKind.power:
                Image(systemName: coordinator.battery.state?.isPluggedIn == true ? "bolt.fill" : "powerplug")
                    .foregroundStyle(coordinator.battery.state?.isPluggedIn == true ? .green : .white)
            default:
                EmptyView()
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
    }
}

/// Çentiğin sağındaki kanat: durum (dalga formu, kalan dakika, şarj yüzdesi).
struct CompactTrailingView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Group {
            switch coordinator.activities.current?.id {
            case AppCoordinator.ActivityKind.nowPlaying:
                // Kapalı notch'ta sürekli animasyon yok (enerji kuralı): durağan simge.
                Image(systemName: "waveform")
                    .foregroundStyle(coordinator.nowPlaying.accentColor.map(Color.init(nsColor:)) ?? .white)
            case AppCoordinator.ActivityKind.meeting:
                if let event = coordinator.calendar.imminentMeeting {
                    // Dakikada bir güncellenir; yalnız toplantı yaklaşırken görünür.
                    TimelineView(.everyMinute) { timeline in
                        Text(event.compactCountdown(at: timeline.date))
                    }
                }
            case AppCoordinator.ActivityKind.power:
                if let state = coordinator.battery.state {
                    Text("%\(state.percent)").monospacedDigit()
                }
            default:
                EmptyView()
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

extension CalendarMonitor.Event {
    var swiftUIColor: Color {
        Color(.sRGB, red: color[safe: 0] ?? 0.5, green: color[safe: 1] ?? 0.5, blue: color[safe: 2] ?? 0.5)
    }

    func compactCountdown(at now: Date) -> String {
        guard start > now else { return "şimdi" }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return "\(minutes) dk"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
