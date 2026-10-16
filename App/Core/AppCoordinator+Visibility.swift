import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Notch'un görünürlüğü: kullanıcının gizlemesi, kilit ekranı ve kompakt kanat durumu.
extension AppCoordinator {
    var isNotchHidden: Bool { (settings.notchHiddenUntil ?? .distantPast) > .now }

    /// Menü çubuğundan gizleme; nil süre = gösterene kadar. Süre dolunca kendiliğinden görünür.
    func hideNotch(for duration: TimeInterval?) {
        settings.notchHiddenUntil = duration.map { Date.now.addingTimeInterval($0) } ?? .distantFuture
        applyNotchHidden()
    }

    /// Yarın sabaha (08.00) kadar.
    func hideNotchUntilTomorrow() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        settings.notchHiddenUntil = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        applyNotchHidden()
    }

    func showNotch() {
        settings.notchHiddenUntil = nil
        applyNotchHidden()
    }

    func applyNotchHidden() {
        let hidden = isNotchHidden
        if !hidden, settings.notchHiddenUntil != nil { settings.notchHiddenUntil = nil }
        panels.isHiddenByUser = hidden
        unhideTask?.cancel()
        if hidden, let until = settings.notchHiddenUntil, until != .distantFuture {
            unhideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.applyNotchHidden()
            }
        }
        AppLog.coordinator.notice("notch \(hidden ? "kullanıcı tarafından gizlendi" : "görünür", privacy: .public)")
        onStatusIconChange?()
    }
    /// Kilitliyken geniş şerit: solda müzik (yoksa pil), sağda pil ya da kalan süre. Kilit ekranında
    /// panel tıklama almıyor ve büyük kart macOS'un saatinin üstüne biner; bu yüzden kompakt yükseklikte.
    /// Öncelik 32: Now Playing'in (30) önünde, çalışan zamanlayıcının (35) ve uyarıların arkasında.
    func updateLockWidget() {
        let hasContent = (settings.nowPlayingEnabled && nowPlaying.info != nil) || (settings.batteryEnabled && battery.state != nil)
        if lockScreen.isLocked, settings.lockScreenWidgetsEnabled, hasContent {
            activities.setLive(ActivityKind.lockWidget, priority: 32)
        } else {
            activities.removeLive(ActivityKind.lockWidget)
        }
    }
    /// Kilit panelinde öne çıkan etkinlik.
    var lockScreenActivityID: ActivityID? {
        activities.current(allowing: ActivityKind.isAllowedOnLockScreen)?.id
    }

    /// Ana notch'ta öne çıkan etkinlik. macOS 27'de normal panel kilit ekranında da görünüyor
    /// (2026-10-15, kullanıcı denemesi); kilitliyken o da kilit kuralına uyar.
    var displayedActivityID: ActivityID? {
        lockScreen.isLocked ? lockScreenActivityID : activities.current?.id
    }
    func updateCompactState() {
        let displayed = displayedActivityID
        for model in panels.models {
            model.setCompact(for: displayed)
        }
        lockScreen.model?.setCompact(for: lockScreenActivityID)
    }
}

private extension NotchSurfaceModel {
    /// Yalnız değişince atar; gözlemciler boşuna tetiklenmesin.
    func setCompact(for id: ActivityID?) {
        let hasContent = id != nil
        let wingWidth = id.map(AppCoordinator.ActivityKind.wantsWideWing) == true ? AppCoordinator.wideWingWidth : nil
        if hasCompactContent != hasContent { hasCompactContent = hasContent }
        if compactWingWidth != wingWidth { compactWingWidth = wingWidth }
    }
}
