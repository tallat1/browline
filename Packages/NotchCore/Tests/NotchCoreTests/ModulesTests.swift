import CoreAudio
import Foundation
import Testing
@testable import Integrations

struct TrackChangeTests {
    let first = NowPlayingInfo(title: "A", artist: "X", playbackRate: 1, isPlaying: true)

    @Test func newTitleOrArtistIsChange() {
        var next = first
        next.title = "B"
        #expect(NowPlayingInfo.isTrackChange(from: first, to: next))
        next = first
        next.artist = "Y"
        #expect(NowPlayingInfo.isTrackChange(from: first, to: next))
    }

    @Test func pauseSeekAndFirstAppearanceAreNot() {
        var paused = first
        paused.isPlaying = false
        paused.title = "B"
        #expect(!NowPlayingInfo.isTrackChange(from: first, to: paused))
        var moved = first
        moved.elapsedTime = 42
        #expect(!NowPlayingInfo.isTrackChange(from: first, to: moved))
        #expect(!NowPlayingInfo.isTrackChange(from: nil, to: first))
    }
}

struct AudioOutputTests {
    @Test func symbolsFromNameThenTransport() {
        typealias Monitor = AudioOutputMonitor
        #expect(Monitor.symbolName(for: .init(id: 1, name: "Talat’s AirPods Pro", transport: .bluetooth)) == "airpodspro")
        #expect(Monitor.symbolName(for: .init(id: 1, name: "AirPods Max", transport: .bluetooth)) == "airpodsmax")
        #expect(Monitor.symbolName(for: .init(id: 1, name: "WH-1000XM5", transport: .bluetooth)) == "headphones")
        #expect(Monitor.symbolName(for: .init(id: 1, name: "MacBook Pro Hoparlörü", transport: .builtIn)) == "laptopcomputer")
        #expect(Monitor.symbolName(for: .init(id: 1, name: "LG", transport: .display)) == "tv")
    }

    @Test func transportMapping() {
        #expect(AudioOutputMonitor.transport(rawValue: kAudioDeviceTransportTypeBluetoothLE) == .bluetooth)
        #expect(AudioOutputMonitor.transport(rawValue: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(AudioOutputMonitor.transport(rawValue: kAudioDeviceTransportTypeVirtual) == .other)
    }
}

@MainActor
struct CountdownTimerTests {
    @Test func remainingProgressAndAdd() {
        let timer = CountdownTimer()
        let start = Date(timeIntervalSince1970: 1000)
        timer.start(seconds: 60, now: start)
        #expect(timer.remaining(at: start.addingTimeInterval(15)) == 45)
        #expect(timer.progress(at: start.addingTimeInterval(15)) == 0.25)
        timer.add(seconds: 60, now: start.addingTimeInterval(15))
        #expect(timer.remaining(at: start.addingTimeInterval(15)) == 105)
        #expect(timer.duration == 120)
        timer.cancel()
        #expect(!timer.isRunning)
    }

    @Test func finishesAndNotifies() async throws {
        let timer = CountdownTimer()
        var finished = false
        timer.onFinished = { finished = true }
        timer.start(seconds: 1)
        try await Task.sleep(for: .milliseconds(1300))
        #expect(finished)
        #expect(!timer.isRunning)
    }

    @Test func formatting() {
        #expect(CountdownTimer.format(65) == "1:05")
        #expect(CountdownTimer.format(0.2) == "0:01")
        #expect(CountdownTimer.format(3725) == "1:02:05")
    }
}

@MainActor
struct KeepAwakeTests {
    /// Gerçek güç iddiası kurulur ve hemen bırakılır; sistemde iz kalmaz.
    @Test func startAndStopReleasesAssertion() {
        let awake = KeepAwake()
        #expect(awake.start(for: .seconds(30), reason: "NotchMVP test"))
        #expect(awake.isActive)
        #expect(awake.endsAt != nil)
        awake.stop()
        #expect(!awake.isActive)
        #expect(awake.endsAt == nil)
    }
}
