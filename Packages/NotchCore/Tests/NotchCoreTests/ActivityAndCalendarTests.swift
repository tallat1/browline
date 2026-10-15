import Foundation
import Testing
@testable import ActivityEngine
@testable import Integrations

@MainActor
struct ActivityCenterTests {
    @Test func highestPriorityLiveWins() {
        let center = ActivityCenter()
        center.setLive("calendar", priority: 10)
        center.setLive("nowPlaying", priority: 20)
        #expect(center.current?.id == "nowPlaying")
        center.removeLive("nowPlaying")
        #expect(center.current?.id == "calendar")
        center.removeLive("calendar")
        #expect(center.current == nil)
    }

    @Test func flashOverridesThenRestores() async throws {
        let center = ActivityCenter()
        center.setLive("nowPlaying", priority: 20)
        center.flash("charging", duration: .milliseconds(50))
        #expect(center.current?.id == "charging")
        try await Task.sleep(for: .milliseconds(200))
        #expect(center.current?.id == "nowPlaying")
    }

    @Test func cancelFlashRestoresImmediately() {
        let center = ActivityCenter()
        center.setLive("nowPlaying", priority: 20)
        center.flash("charging", duration: .seconds(10))
        center.cancelFlash("charging")
        #expect(center.current?.id == "nowPlaying")
    }

    /// Kilit ekranı: izinsiz etkinlik öndeyken arkadaki izinli etkinlik görünür.
    @Test func filteredCurrentSkipsDisallowed() {
        let center = ActivityCenter()
        center.setLive("meeting", priority: 40)
        center.setLive("nowPlaying", priority: 30)
        center.flash("downloadDone", duration: .seconds(60))
        let allowed: (ActivityID) -> Bool = { $0 == "nowPlaying" || $0 == "power" }
        #expect(center.current?.id == "downloadDone")
        #expect(center.current(allowing: allowed)?.id == "nowPlaying")
        center.flash("power", duration: .seconds(60))
        #expect(center.current(allowing: allowed)?.id == "power")
        center.cancelFlash("power")
        center.removeLive("nowPlaying")
        #expect(center.current(allowing: allowed) == nil)
    }

    /// Öne çıkan değişmese de bildirilir; çağrıldığında current güncel olmalı.
    @Test func activitiesChangedFiresAfterCurrentUpdates() {
        let center = ActivityCenter()
        var seen: [ActivityID?] = []
        center.onActivitiesChanged = { seen.append(center.current?.id) }
        center.setLive("meeting", priority: 40)
        center.setLive("nowPlaying", priority: 30)
        #expect(seen == ["meeting", "meeting"])
    }
}

struct MeetingLinkTests {
    @Test func findsLinkInNotes() {
        let url = MeetingLink.find(url: nil, location: "Ofis 3",
                                   notes: "Katıl: https://us02web.zoom.us/j/123456?pwd=abc lütfen")
        #expect(url?.host == "us02web.zoom.us")
    }

    @Test func prefersEventURL() {
        let meet = URL(string: "https://meet.google.com/abc-defg-hij")!
        #expect(MeetingLink.find(url: meet, location: "https://zoom.us/j/1", notes: nil) == meet)
    }

    @Test func ignoresOtherLinks() {
        #expect(MeetingLink.find(url: URL(string: "https://example.com"), location: nil,
                                 notes: "https://evil-zoom.us.example.com/j/1") == nil)
    }
}

@MainActor
struct ShelfStoreTests {
    @Test func addDeduplicatesAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("a.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShelfStore(directory: directory)
        store.add([file, file])
        #expect(store.items.count == 1)
        #expect(ShelfStore(directory: directory).items.count == 1)

        try FileManager.default.removeItem(at: file)
        #expect(store.resolvedURLs.isEmpty)
        #expect(store.items.isEmpty)
    }
}
