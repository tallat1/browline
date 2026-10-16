import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

extension CalendarMonitor.Event {
    var swiftUIColor: Color {
        Color(.sRGB, red: color[safe: 0] ?? 0.5, green: color[safe: 1] ?? 0.5, blue: color[safe: 2] ?? 0.5)
    }

    func compactCountdown(at now: Date) -> String {
        guard start > now else { return String(localized: "şimdi") }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return String(localized: "\(minutes) dk")
    }
}
