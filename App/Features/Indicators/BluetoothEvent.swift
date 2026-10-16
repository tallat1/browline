import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Bluetooth kısa bildirimi: hangi aygıt, ne oldu.
struct BluetoothEvent: Equatable {
    enum Change: Equatable {
        case connected, disconnected
        case lowBattery(Int)
    }

    let device: BluetoothMonitor.Device
    let change: Change
    let date: Date
}
