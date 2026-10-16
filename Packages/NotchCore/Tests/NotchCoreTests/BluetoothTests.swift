import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

@MainActor
struct BluetoothMonitorTests {
    // system_profiler -json çıktısının özü (2026-10-16, macOS 27, Türkçe bölge: "%80").
    static let sample = #"{"SPBluetoothDataType":[{"device_connected":[{"Ada (AirPods Pro)":{"device_batteryLevelCase":"%15","device_batteryLevelLeft":"%80","device_batteryLevelRight":"%79","device_minorType":"Headphones"}},{"Ada (AirPods Pro)":{"device_batteryLevelCase":"%15"}},{"Magic Keyboard":{"device_batteryLevelMain":"18%","device_minorType":"Keyboard"}}],"device_not_connected":[{"Eski":{}}]}]}"#

    @Test func parsesAndMergesDevices() {
        let devices = BluetoothMonitor.parse(Data(Self.sample.utf8))
        #expect(devices.map(\.name) == ["Ada (AirPods Pro)", "Magic Keyboard"])
        #expect(devices[0].kind == .headphones)
        #expect(devices[0].left == 80)
        #expect(devices[0].right == 79)
        #expect(devices[0].caseLevel == 15)
        #expect(devices[0].lowest == 79)  // kutu hariç
        #expect(devices[1].kind == .keyboard)
        #expect(devices[1].main == 18)
    }

    @Test func shortNameDropsOwner() {
        func short(_ name: String) -> String { BluetoothMonitor.Device(name: name, kind: .other).shortName }
        #expect(short("Ada (AirPods Pro)") == "AirPods Pro")
        #expect(short("Ada’s Magic Keyboard") == "Magic Keyboard")
        #expect(short("MX Master 3") == "MX Master 3")
        #expect(short("(Boş)") == "(Boş)")
    }

    @Test func connectDisconnectAndLowBatteryOnce() {
        let monitor = BluetoothMonitor()
        var connected: [String] = [], disconnected: [String] = [], low: [String] = []
        monitor.onConnected = { connected.append($0.name) }
        monitor.onDisconnected = { disconnected.append($0.name) }
        monitor.onLowBattery = { device, level in low.append("\(device.name) \(level)") }
        let keyboard = BluetoothMonitor.Device(name: "Klavye", kind: .keyboard, main: 50)
        monitor.apply([keyboard])  // ilk okuma: bağlandı sayılmaz
        #expect(connected.isEmpty)
        let mouse = BluetoothMonitor.Device(name: "Fare", kind: .mouse, main: 18)
        monitor.apply([keyboard, mouse])
        monitor.apply([keyboard, mouse])  // aynı eşik ikinci kez uyarılmaz
        #expect(connected == ["Fare"])
        #expect(low == ["Fare 18"])
        var drained = mouse
        drained.main = 9
        monitor.apply([keyboard, drained])
        #expect(low == ["Fare 18", "Fare 9"])
        monitor.apply([keyboard])
        #expect(disconnected == ["Fare"])
    }
}
