import Foundation
import Testing
@testable import Integrations

struct AdapterStreamParserTests {
    @Test func fullPayloadThenDiff() {
        var parser = AdapterStreamParser()
        let full = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","playing":true,"title":"Song","artist":"Band","durationMicros":200000000,"elapsedTimeMicros":10000000,"timestampEpochMicros":1760000000000000,"playbackRate":1}}"#
        let first = parser.consume(line: full)
        guard case let .playing(info) = first else {
            Issue.record("çalan medya bekleniyordu")
            return
        }
        #expect(info.title == "Song")
        #expect(info.artist == "Band")
        #expect(info.duration == 200)
        #expect(info.elapsedTime == 10)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_760_000_000))

        // Diff: yalnız değişen anahtar; null anahtar kaldırılır.
        let diff = #"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#
        let second = parser.consume(line: diff)
        guard case let .playing(paused) = second else {
            Issue.record("duraklatılmış medya bekleniyordu")
            return
        }
        #expect(paused.isPlaying == false)
        #expect(paused.artist == nil)
        #expect(paused.title == "Song")
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        var parser = AdapterStreamParser()
        #expect(parser.consume(line: #"{"type":"data","diff":false,"payload":{}}"#) == .nothingPlaying)
    }

    @Test func duplicateUpdatesAreSuppressed() {
        var parser = AdapterStreamParser()
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","playing":true,"title":"t"}}"#
        #expect(parser.consume(line: line) != nil)
        #expect(parser.consume(line: line) == nil)
    }

    @Test func garbageIsIgnored() {
        var parser = AdapterStreamParser()
        #expect(parser.consume(line: "not json") == nil)
        #expect(parser.consume(line: #"{"type":"other"}"#) == nil)
    }

    @Test func missingTitleIsInvalid() {
        var parser = AdapterStreamParser()
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","playing":true}}"#
        #expect(parser.consume(line: line) == .nothingPlaying)
    }

    @Test func artworkIsDecoded() {
        var parser = AdapterStreamParser()
        let base64 = Data([1, 2, 3]).base64EncodedString()
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","playing":true,"title":"t","artworkData":"\#(base64)"}}"#
        let update = parser.consume(line: line)
        guard case let .playing(info) = update else {
            Issue.record("çalan medya bekleniyordu")
            return
        }
        #expect(info.artworkData == Data([1, 2, 3]))
    }
}

struct NowPlayingInfoTests {
    @Test func elapsedAdvancesWhilePlayingAndClampsToDuration() {
        let start = Date(timeIntervalSince1970: 1000)
        let info = NowPlayingInfo(title: "t", duration: 100, elapsedTime: 10, timestamp: start,
                                  playbackRate: 1, isPlaying: true)
        #expect(info.elapsed(at: start.addingTimeInterval(5)) == 15)
        #expect(info.elapsed(at: start.addingTimeInterval(500)) == 100)
    }

    @Test func elapsedIsFrozenWhenPaused() {
        let start = Date(timeIntervalSince1970: 1000)
        let info = NowPlayingInfo(title: "t", duration: 100, elapsedTime: 10, timestamp: start,
                                  playbackRate: 0, isPlaying: false)
        #expect(info.elapsed(at: start.addingTimeInterval(30)) == 10)
    }
}

@MainActor
struct PlayerNotificationTests {
    @Test func musicNotification() throws {
        let info = try #require(PlayerNotificationSource.parse(
            ["Name": "Song", "Artist": "Band", "Player State": "Playing", "Total Time": 180_000],
            bundleIdentifier: "com.apple.Music"))
        #expect(info.isPlaying)
        #expect(info.duration == 180)
    }

    @Test func stoppedPlayerIsNothing() {
        #expect(PlayerNotificationSource.parse(["Name": "Song", "Player State": "Stopped"],
                                               bundleIdentifier: "com.apple.Music") == nil)
    }
}

struct MediaControlTests {
    @Test func parserReadsShuffleAndRepeat() throws {
        var parser = AdapterStreamParser()
        let line = #"{"type":"data","diff":false,"payload":{"title":"A","bundleIdentifier":"com.apple.Music","playing":true,"shuffleMode":3,"repeatMode":2}}"#
        guard case let .playing(info)? = parser.consume(line: line) else { Issue.record("çalan yok"); return }
        #expect(info.shuffleMode == 3)
        #expect(info.repeatMode == 2)
    }

    @Test func modeCycles() {
        #expect(NowPlayingController.nextShuffleMode(after: 1) == 3)
        #expect(NowPlayingController.nextShuffleMode(after: 3) == 1)
        #expect(NowPlayingController.nextRepeatMode(after: 1) == 3)
        #expect(NowPlayingController.nextRepeatMode(after: 3) == 2)
        #expect(NowPlayingController.nextRepeatMode(after: 2) == 1)
    }
}
