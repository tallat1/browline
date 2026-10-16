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
            CompactLeadingView(coordinator: coordinator, activityID: coordinator.displayedActivityID)
        } compactTrailing: {
            CompactTrailingView(coordinator: coordinator, activityID: coordinator.displayedActivityID)
        } expanded: { context in
            // Kilitte panel açılmıyor (2026-10-15 günlüğü: kilit süresince hover yok); yine de
            // açılırsa raf, takvim ve etkinlikler kilit ekranına düşmesin.
            if !coordinator.lockScreen.isLocked {
                ExpandedView(context: context, model: model, coordinator: coordinator)
            }
        }
        .environment(\.pausesContinuousMotion, coordinator.isMotionPaused)
    }
}
