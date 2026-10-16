import AppKit
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
        #expect(Monitor.symbolName(for: .init(id: 1, name: "Ada’s AirPods Pro", transport: .bluetooth)) == "airpodspro")
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

struct SpectrumAnalyzerTests {
    static func sine(_ frequency: Double, seconds: Double = 0.5, rate: Double = 48_000, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    @Test func bassToneLightsFirstBand() {
        let levels = SpectrumLevels()
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000, output: levels)
        analyzer.consume(mono: Self.sine(80))
        let result = levels.read()
        #expect(result.hasSignal)
        #expect(result.values[0] > 0.8)
        #expect(result.values[3] < result.values[0])
    }

    @Test func trebleToneLightsLastBand() {
        let levels = SpectrumLevels()
        let analyzer = SpectrumAnalyzer(sampleRate: 44_100, output: levels)
        // Önce bas: tepeler oturur; sonra tiz, bas bandı iner.
        analyzer.consume(mono: Self.sine(80, rate: 44_100))
        analyzer.consume(mono: Self.sine(5_000, rate: 44_100))
        let result = levels.read()
        #expect(result.values[3] > 0.8)
        #expect(result.values[0] < 0.5)
    }

    /// 6 dB'lik vuruşlar (müzikte tipik) çubuğu belirgin oynatmalı; 30 dB aralıkta tepede kalıyordu.
    @Test func sixDecibelBeatsSwingTheBar() {
        let levels = SpectrumLevels()
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000, output: levels)
        let rate = 48_000.0
        let signal: [Float] = (0..<Int(3 * rate)).map { index in
            let time = Double(index) / rate
            let loud = Int(time / 0.25) % 2 == 0
            return (loud ? 0.3 : 0.15) * Float(sin(2 * .pi * 80 * time))
        }
        var observed: [Float] = []
        for start in stride(from: 0, to: signal.count, by: SpectrumAnalyzer.fftSize) {
            analyzer.consume(mono: Array(signal[start..<min(signal.count, start + SpectrumAnalyzer.fftSize)]))
            if start > signal.count / 2 { observed.append(levels.read().values[0]) }
        }
        let swing = (observed.max() ?? 0) - (observed.min() ?? 0)
        #expect(swing > 0.4, "salınım \(swing)")
    }

    @Test func silenceIsNoSignal() {
        let levels = SpectrumLevels()
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000, output: levels)
        analyzer.consume(mono: [Float](repeating: 0, count: 4_096))
        #expect(!levels.read().hasSignal)
        #expect(levels.read().values.allSatisfy { $0 == 0 })
    }

    @Test func bandsCoverAudibleRange() {
        let bins = SpectrumAnalyzer.binRanges(sampleRate: 48_000)
        #expect(bins.count == SpectrumLevels.bandCount)
        #expect(zip(bins, bins.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
        #expect(bins.allSatisfy { !$0.isEmpty })
    }
}
