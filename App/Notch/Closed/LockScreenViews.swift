import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

/// Kilit ekranındaki notch: yalnız kompakt, yalnız kişisel içerik taşımayan etkinlikler.
/// Panel olay almadığı için açılmaz; açık görünüm boş.
struct LockScreenRootView: View {
    let model: NotchSurfaceModel
    let coordinator: AppCoordinator

    var body: some View {
        NotchSurfaceView(model: model) {
            CompactLeadingView(coordinator: coordinator, activityID: coordinator.lockScreenActivityID)
        } compactTrailing: {
            CompactTrailingView(coordinator: coordinator, activityID: coordinator.lockScreenActivityID)
        } expanded: { _ in
            EmptyView()
        }
        .environment(\.pausesContinuousMotion, coordinator.isMotionPaused)
    }
}

/// Kilit şeridinin sağı: müzik çalıyorsa pil; müzik yoksa (solda pil) kalan ya da dolma süresi.
struct LockWidgetTrailing: View {
    let coordinator: AppCoordinator

    var body: some View {
        if let state = coordinator.battery.state {
            if coordinator.nowPlaying.info != nil, coordinator.settings.nowPlayingEnabled {
                HStack(spacing: 4) {
                    Text(verbatim: NowFormat.percent(Double(state.percent))).monospacedDigit()
                    Image(systemName: state.symbolName)
                        .foregroundStyle(state.isCharging ? .green : (state.percent <= 20 ? .red : .secondary))
                }
                .foregroundStyle(.secondary)
            } else if let text = Self.remaining(state) {
                Text(text).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    /// "1 sa 20 dk kaldı" / "dolmasına 35 dk"; sistem hesaplamıyorsa nil.
    static func remaining(_ state: BatteryMonitor.State) -> String? {
        let minutes = state.isCharging ? state.minutesToFull : (state.isPluggedIn ? nil : state.minutesToEmpty)
        guard let minutes, minutes > 0 else { return state.isPluggedIn && !state.isCharging ? String(localized: "Şarj tamam") : nil }
        let duration = minutes >= 60 ? String(localized: "\(minutes / 60) sa \(minutes % 60) dk") : String(localized: "\(minutes) dk")
        return state.isCharging ? String(localized: "dolmasına \(duration)") : String(localized: "\(duration) kaldı")
    }
}
