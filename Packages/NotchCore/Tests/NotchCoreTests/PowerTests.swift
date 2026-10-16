import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

@MainActor
struct KeepAwakeTests {
    /// Gerçek güç iddiası kurulur ve hemen bırakılır; sistemde iz kalmaz.
    @Test func startAndStopReleasesAssertion() {
        let awake = KeepAwake()
        #expect(awake.start(for: .seconds(30), reason: "Browline test"))
        #expect(awake.isActive)
        #expect(awake.endsAt != nil)
        awake.stop()
        #expect(!awake.isActive)
        #expect(awake.endsAt == nil)
    }
}

struct BatteryAlertTests {
    func state(_ percent: Int, plugged: Bool = false) -> BatteryMonitor.State {
        BatteryMonitor.State(percent: percent, isCharging: plugged && percent < 100, isPluggedIn: plugged)
    }

    @Test func lowAlertsOnlyWhenCrossingDown() {
        #expect(BatteryMonitor.alert(from: state(21), to: state(20)) == .low(percent: 20))
        #expect(BatteryMonitor.alert(from: state(11), to: state(10)) == .low(percent: 10))
        #expect(BatteryMonitor.alert(from: state(20), to: state(19)) == nil)
        #expect(BatteryMonitor.alert(from: state(21, plugged: true), to: state(20, plugged: true)) == nil)
        #expect(BatteryMonitor.alert(from: nil, to: state(5)) == nil)
    }

    @Test func fullWhenReachingHundredOnPower() {
        #expect(BatteryMonitor.alert(from: state(99, plugged: true), to: state(100, plugged: true)) == .full)
        #expect(BatteryMonitor.alert(from: state(100, plugged: true), to: state(100, plugged: true)) == nil)
    }
}
