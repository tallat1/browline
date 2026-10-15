import ActivityAPI
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
                if let activity = coordinator.externalActivity(for: coordinator.activities.current?.id) {
                    HStack(spacing: 6) {
                        Image(systemName: activity.symbolName).foregroundStyle(activity.tintColor)
                        Text(activity.title).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                }
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
                if let activity = coordinator.externalActivity(for: coordinator.activities.current?.id) {
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        if let progress = activity.progress {
                            Text("%\(Int((progress * 100).rounded()))").monospacedDigit()
                            ProgressRing(progress: progress, tint: activity.tintColor)
                                .frame(width: 14, height: 14)
                        } else if let subtitle = activity.subtitle {
                            Text(subtitle).lineLimit(1).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 4)
                }
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

struct ProgressRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

extension ExternalActivity {
    /// Geçersiz ya da bu sistemde olmayan sembol adı yerine genel simge.
    var symbolName: String {
        guard let symbol, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
            return "app.badge"
        }
        return symbol
    }

    var tintColor: Color {
        guard let tint, tint.count == 7, let value = UInt32(tint.dropFirst(), radix: 16) else { return .white }
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
