import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

extension BatteryMonitor.State {
    var symbolName: String {
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
