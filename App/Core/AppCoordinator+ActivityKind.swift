import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Kapalı notch'ta görünen etkinliklerin kimlikleri, öncelik kuralları ve gösterim süreleri.
extension AppCoordinator {
    enum ActivityKind {
        static let nowPlaying: ActivityID = "nowPlaying"
        static let meeting: ActivityID = "meeting"
        static let power: ActivityID = "power"
        /// Dış etkinlikler "ext." önekiyle; kısa bildirim tek kimlikte.
        static let externalPrefix = "ext."
        static let externalFlash: ActivityID = "ext.flash"
        /// Onay sorusu toplantıdan (40) ve Now Playing'den (30) önde.
        static let questionPriority = 48
        static let privacy: ActivityID = "privacy"
        static let hud: ActivityID = "hud"
        static let download: ActivityID = "download"
        static let downloadDone: ActivityID = "downloadDone"
        static let trackChange: ActivityID = "trackChange"
        static let audioOutput: ActivityID = "audioOutput"
        static let keepAwake: ActivityID = "keepAwake"
        static let timer: ActivityID = "timer"
        static let timerDone: ActivityID = "timerDone"
        static let batteryLow: ActivityID = "batteryLow"
        static let batteryFull: ActivityID = "batteryFull"
        static let claudeUsage: ActivityID = "claudeUsage"
        static let bluetooth: ActivityID = "bluetooth"
        static let microphone: ActivityID = "microphone"
        static let screenRecording: ActivityID = "screenRecording"
        static let ci: ActivityID = "ci"
        /// Kilitliyken müzik + pil şeridi (kilit ekranı bileşeni).
        static let lockWidget: ActivityID = "lockWidget"
        static let ciDone: ActivityID = "ciDone"

        /// Başlık ya da çubuk taşıyan etkinlikler geniş kanat ister.
        static func wantsWideWing(_ id: ActivityID) -> Bool {
            id.rawValue.hasPrefix(externalPrefix)
                || [hud, download, downloadDone, trackChange, audioOutput, timerDone, batteryLow, batteryFull,
                    claudeUsage, bluetooth, microphone, ci, ciDone, lockWidget].contains(id)
        }

        /// Kilit ekranında yalnız kişisel içerik taşımayanlar: toplantı başlığı, dosya adı ve dış
        /// etkinlik metni bilgisayarın başındaki herkese görünür.
        static func isAllowedOnLockScreen(_ id: ActivityID) -> Bool {
            [nowPlaying, power, privacy, hud, timer, timerDone, keepAwake, batteryLow, batteryFull, microphone,
             screenRecording, lockWidget].contains(id)
        }
    }

    /// Başlık taşıyan dış etkinlikler için kompakt kanat genişliği.
    static let wideWingWidth: CGFloat = 136

    /// Şarkı önizlemesinin süresi: kısa adda 3 sn; uzun ad kayarak sonuna kadar okunabilsin diye
    /// kayan yazının bir turu kadar.
    static func trackPeekDuration(for title: String) -> Duration {
        // Geniş kanatta başlığa kalan genişlik: kanat − baş boşluk (10) − kapak (20) − aralık (6).
        readableFlashDuration(base: .seconds(3), text: title, available: wideWingWidth - 36)
    }

    /// Kısa bildirimin süresi: en az `base`; metin geniş kanada sığmıyorsa kayan yazının bir turu
    /// kadar. Ürün genelinde tek kural: bildirim, metni okunmadan kaybolmaz.
    static func readableFlashDuration(base: Duration, text: String,
                                      available: CGFloat = WideWingLabel.textWidth) -> Duration {
        let overflow = MarqueeText.width(of: text, size: 13, weight: .semibold) - available
        let needed = Duration.milliseconds(Int((NotchMotion.marqueeCycle(overflow: overflow) + 0.4) * 1000))
        return max(base, needed)
    }
}
