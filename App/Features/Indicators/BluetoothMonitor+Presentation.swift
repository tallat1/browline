import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

extension BluetoothMonitor.Device {
    var symbolName: String {
        switch kind {
        case .headphones:
            if name.localizedCaseInsensitiveContains("AirPods Pro") { "airpodspro" }
            else if name.localizedCaseInsensitiveContains("AirPods Max") { "airpodsmax" }
            else if name.localizedCaseInsensitiveContains("AirPods") { "airpods" }
            else { "headphones" }
        case .keyboard: "keyboard"
        case .mouse: "magicmouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .speaker: "hifispeaker"
        case .gamepad: "gamecontroller"
        case .other: "wave.3.right"
        }
    }

    /// Kulaklıkta sol/sağ/kutu ayrı; diğerlerinde tek pil.
    var batteryHelp: String {
        var parts: [String] = []
        if let main { parts.append(NowFormat.percent(Double(main))) }
        if let left { parts.append(String(localized: "sol \(NowFormat.percent(Double(left)))")) }
        if let right { parts.append(String(localized: "sağ \(NowFormat.percent(Double(right)))")) }
        if let caseLevel { parts.append(String(localized: "kutu \(NowFormat.percent(Double(caseLevel)))")) }
        return ([name] + parts).joined(separator: " · ")
    }

    static func batterySymbol(for level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
