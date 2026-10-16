import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

extension HUDController {
    var symbolName: String {
        switch kind {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if isMuted || level == 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }

    var title: String {
        switch kind {
        case .brightness: String(localized: "Parlaklık")
        case .volume: isMuted ? String(localized: "Sessiz") : String(localized: "Ses")
        }
    }
}
