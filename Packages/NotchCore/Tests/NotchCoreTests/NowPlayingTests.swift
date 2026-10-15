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

struct MediaSessionsTests {
    // Sahte veri: yardımcının iki oturumlu satırı (Chrome duraklatılmış video, Spotify çalan şarkı).
    static let twoSessions = #"{"type":"sessions","sessions":[{"processIdentifier":2828,"bundleIdentifier":"com.google.Chrome","displayName":"Google Chrome","playing":false,"title":"Video","durationMicros":492000000,"elapsedTimeMicros":19000000,"playbackRate":0,"artworkData":"AQID"},{"processIdentifier":2835,"bundleIdentifier":"com.spotify.client","displayName":"Spotify","playing":true,"title":"Song","artist":"Band","playbackRate":1}]}"#

    @Test func parserReadsEverySession() throws {
        var parser = MediaSessionsParser()
        let parsed = parser.consume(line: Self.twoSessions)
        let sessions = try #require(parsed)
        #expect(sessions.map(\.id) == ["pid:2828", "pid:2835"])
        #expect(sessions[0].info.isPlaying == false)
        #expect(sessions[0].info.processIdentifier == 2828)
        #expect(sessions[0].info.artworkData == Data([1, 2, 3]))
        #expect(sessions[0].appBundleIdentifier == "com.google.Chrome")
        #expect(sessions[1].info.artist == "Band")
        #expect(sessions[1].info.artworkData == nil)
    }

    @Test func artworkIsKeptUntilChangedOrCleared() throws {
        var parser = MediaSessionsParser()
        _ = parser.consume(line: Self.twoSessions)
        // Kapaksız satır = kapak aynı; yalnız durum değişti.
        let paused = #"{"type":"sessions","sessions":[{"processIdentifier":2828,"bundleIdentifier":"com.google.Chrome","playing":true,"title":"Video"}]}"#
        let parsedKept = parser.consume(line: paused)
        let kept = try #require(parsedKept)
        #expect(kept.first?.info.artworkData == Data([1, 2, 3]))
        let cleared = #"{"type":"sessions","sessions":[{"processIdentifier":2828,"bundleIdentifier":"com.google.Chrome","playing":true,"title":"Video","artworkData":null}]}"#
        let afterClear = parser.consume(line: cleared)
        #expect(afterClear?.first?.info.artworkData == nil)
        #expect(afterClear != nil)
        #expect(parser.consume(line: cleared) == nil)
    }

    @Test func supportedCommandsAreRead() throws {
        var parser = MediaSessionsParser()
        let line = #"{"type":"sessions","sessions":[{"processIdentifier":1,"bundleIdentifier":"com.google.Chrome","playing":true,"title":"V","commands":[0,1,2,24]},{"processIdentifier":2,"bundleIdentifier":"x","playing":false,"title":"S"}]}"#
        let parsed = parser.consume(line: line)
        let sessions = try #require(parsed)
        #expect(!sessions[0].supports(.nextTrack))
        #expect(sessions[0].supports(.togglePlayPause))
        // Bilinmiyorsa hepsi varsayılır.
        #expect(sessions[1].supports(.nextTrack))
    }

    @Test func browserPlayerUsesParentAppForIcon() throws {
        var parser = MediaSessionsParser()
        let line = #"{"type":"sessions","sessions":[{"processIdentifier":7,"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","playing":true,"title":"Clip"}]}"#
        let sessions = parser.consume(line: line)
        #expect(sessions?.first?.appBundleIdentifier == "com.apple.Safari")
    }

    private static func session(_ pid: Int32, playing: Bool) -> MediaSession {
        MediaSession(id: "pid:\(pid)", info: NowPlayingInfo(bundleIdentifier: "b\(pid)", title: "t\(pid)",
                                                            isPlaying: playing, processIdentifier: pid))
    }

    @Test func playingSessionWinsOverPausedSystemChoice() {
        // Sistem duraklatılmış videoyu seçmiş; çalan şarkı gizlenmemeli.
        let sessions = [Self.session(1, playing: false), Self.session(2, playing: true)]
        #expect(MediaSession.focus(in: sessions, selected: nil, system: "pid:1", playStartedAt: [:])?.id == "pid:2")
    }

    @Test func systemChoiceWinsWhenBothPlay() {
        let sessions = [Self.session(1, playing: true), Self.session(2, playing: true)]
        #expect(MediaSession.focus(in: sessions, selected: nil, system: "pid:1",
                                   playStartedAt: ["pid:2": .now])?.id == "pid:1")
        // Sistem seçimi yoksa en son çalmaya başlayan.
        #expect(MediaSession.focus(in: sessions, selected: nil, system: nil,
                                   playStartedAt: ["pid:1": .distantPast, "pid:2": .now])?.id == "pid:2")
    }

    @Test func manualSelectionWinsAndFallsBackWhenGone() {
        let sessions = [Self.session(1, playing: false), Self.session(2, playing: true)]
        #expect(MediaSession.focus(in: sessions, selected: "pid:1", system: nil, playStartedAt: [:])?.id == "pid:1")
        #expect(MediaSession.focus(in: sessions, selected: "pid:9", system: nil, playStartedAt: [:])?.id == "pid:2")
        // Hiçbiri çalmıyorsa sistemin seçtiği.
        let paused = [Self.session(1, playing: false), Self.session(2, playing: false)]
        #expect(MediaSession.focus(in: paused, selected: nil, system: "pid:2", playStartedAt: [:])?.id == "pid:2")
    }

    @Test func sessionMatchesSystemByProcessThenBundle() {
        let session = Self.session(5, playing: true)
        #expect(session.matches(NowPlayingInfo(bundleIdentifier: "other", title: "x", isPlaying: true, processIdentifier: 5)))
        #expect(!session.matches(NowPlayingInfo(bundleIdentifier: "b5", title: "x", isPlaying: true, processIdentifier: 6)))
        #expect(session.matches(NowPlayingInfo(bundleIdentifier: "b5", title: "x", isPlaying: true)))
    }

    @Test func adapterParserReadsProcessIdentifier() throws {
        var parser = AdapterStreamParser()
        let line = #"{"type":"data","diff":false,"payload":{"title":"A","bundleIdentifier":"com.google.Chrome","playing":false,"processIdentifier":2828}}"#
        guard case let .playing(info)? = parser.consume(line: line) else { Issue.record("çalan yok"); return }
        #expect(info.processIdentifier == 2828)
    }
}
