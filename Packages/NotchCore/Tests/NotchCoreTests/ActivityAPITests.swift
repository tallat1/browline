import Foundation
import Testing
@testable import ActivityAPI

struct ActivityValidationTests {
    @Test func acceptsWellFormedPush() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let activity = try ExternalActivity.validated(
            from: ActivityRequest(op: .push, id: "build.1", title: " Derleme ", progress: 0.4, symbol: "hammer",
                                  tint: "#FF8800", ttl: 30),
            now: now)
        #expect(activity.title == "Derleme")
        #expect(activity.priority == ExternalActivity.defaultPriority)
        #expect(activity.expiresAt == now.addingTimeInterval(30))
    }

    @Test(arguments: [
        ActivityRequest(op: .push, title: "x"),
        ActivityRequest(op: .push, id: "bad id", title: "x"),
        ActivityRequest(op: .push, id: "a"),
        ActivityRequest(op: .push, id: "a", title: "x", progress: 1.5),
        ActivityRequest(op: .push, id: "a", title: "x", symbol: "Hammer!"),
        ActivityRequest(op: .push, id: "a", title: "x", tint: "orange"),
        ActivityRequest(op: .push, id: "a", title: "x", priority: 99),
        ActivityRequest(op: .push, id: "a", title: "x", ttl: 0),
        ActivityRequest(op: .push, id: "a", title: String(repeating: "x", count: 81)),
    ])
    func rejectsOutOfRange(_ request: ActivityRequest) {
        #expect(throws: ExternalActivity.ValidationError.self) {
            try ExternalActivity.validated(from: request)
        }
    }
}

@MainActor
struct ExternalActivityStoreTests {
    @Test func reservedIDsAreInternalOnly() {
        let store = ExternalActivityStore()
        #expect(!store.handle(ActivityRequest(op: .push, id: "notch.question", title: "Sahte")).ok)
        #expect(store.handle(ActivityRequest(op: .push, id: "notch.question", title: "Soru"), isInternal: true).ok)
        #expect(!store.handle(ActivityRequest(op: .end, id: "notch.question")).ok)
        #expect(store.activities.map(\.id) == ["notch.question"])
    }

    @Test func pushUpdatesInPlaceAndEndRemoves() {
        let store = ExternalActivityStore()
        #expect(store.handle(ActivityRequest(op: .push, id: "a", title: "Bir")).ok)
        #expect(store.handle(ActivityRequest(op: .push, id: "a", title: "İki")).ok)
        #expect(store.activities.map(\.title) == ["İki"])
        #expect(store.handle(ActivityRequest(op: .end, id: "a")).ok)
        #expect(store.activities.isEmpty)
        #expect(!store.handle(ActivityRequest(op: .end, id: "a")).ok)
    }

    @Test func limitsActivityCount() {
        let store = ExternalActivityStore()
        for index in 0..<ExternalActivityStore.maximumActivities {
            #expect(store.handle(ActivityRequest(op: .push, id: "a\(index)", title: "x")).ok)
        }
        #expect(!store.handle(ActivityRequest(op: .push, id: "overflow", title: "x")).ok)
    }

    @Test func expiredActivitiesAreRemoved() {
        let store = ExternalActivityStore()
        let start = Date(timeIntervalSince1970: 1000)
        _ = store.handle(ActivityRequest(op: .push, id: "short", title: "x", ttl: 5), now: start)
        _ = store.handle(ActivityRequest(op: .push, id: "long", title: "x", ttl: 500), now: start)
        store.removeExpired(now: start.addingTimeInterval(10))
        #expect(store.activities.map(\.id) == ["long"])
    }

    @Test func higherPriorityFirst() {
        let store = ExternalActivityStore()
        _ = store.handle(ActivityRequest(op: .push, id: "low", title: "x", priority: 5))
        _ = store.handle(ActivityRequest(op: .push, id: "high", title: "x", priority: 45))
        #expect(store.activities.first?.id == "high")
    }
}

/// Gerçek Unix soketi üzerinden uçtan uca: sunucu, istemci ve durum birlikte.
@MainActor
struct ActivitySocketTests {
    @Test func roundTripOverSocket() async throws {
        let url = URL(fileURLWithPath: "/tmp/ntest-\(UUID().uuidString.prefix(8)).sock")
        let store = ExternalActivityStore()
        let server = ActivitySocketServer(socketURL: url) { request in
            await MainActor.run { store.handle(request) }
        }
        try server.start()
        defer { server.stop() }

        // Sunucunun yanıtı ana aktörde üretildiği için istemci arka planda çalışmalı.
        let response = try await Task.detached {
            try ActivitySocketClient.send(ActivityRequest(op: .push, id: "build", title: "Derleme", progress: 0.5),
                                          socketURL: url)
        }.value
        #expect(response.ok)
        #expect(store.activities.first?.progress == 0.5)

        let list = try await Task.detached {
            try ActivitySocketClient.send(ActivityRequest(op: .list), socketURL: url)
        }.value
        #expect(list.activities?.map(\.id) == ["build"])

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func clientReportsNotRunning() {
        #expect(throws: ActivitySocketClient.ClientError.self) {
            try ActivitySocketClient.send(ActivityRequest(op: .ping), socketURL: URL(fileURLWithPath: "/tmp/ntest-none.sock"))
        }
    }
}

struct ActivityURLTests {
    @Test func parsesPushWithPercentProgress() throws {
        let url = try #require(URL(string: "browline://push?id=build&title=Derleme%20%C3%A7al%C4%B1%C5%9F%C4%B1yor&progress=40%25&symbol=hammer&tint=%23FF9F0A&priority=35&ttl=120"))
        let request = try ActivityURL.request(from: url)
        #expect(request == ActivityRequest(op: .push, id: "build", title: "Derleme çalışıyor", progress: 0.4,
                                           symbol: "hammer", tint: "#FF9F0A", priority: 35, ttl: 120))
    }

    @Test func parsesEndAndFlash() throws {
        #expect(try ActivityURL.request(from: #require(URL(string: "browline://end?id=build")))
            == ActivityRequest(op: .end, id: "build"))
        #expect(try ActivityURL.request(from: #require(URL(string: "browline:flash?title=Bitti&duration=2")))
            == ActivityRequest(op: .flash, title: "Bitti", duration: 2))
    }


    @Test(arguments: [
        ("https://push?id=a", ActivityURL.ParseError.scheme),
        ("browline://list", .operation("list")),
        ("browline://push?id=a&title=b&color=red", .unknownParameter("color")),
        ("browline://push?id=a&title=b&progress=yarım", .number("progress")),
        // Int(Double) bunlarda çöküyordu: web bağlantısıyla uygulama düşürülebiliyordu.
        ("browline://push?id=a&title=b&priority=1e999", .number("priority")),
        ("browline://push?id=a&title=b&priority=nan", .number("priority")),
        ("browline://push?id=a&title=b&priority=1e300", .number("priority")),
        ("browline://push?id=a&title=b&ttl=inf", .number("ttl")),
    ])
    func rejectsMalformed(_ raw: String, _ expected: ActivityURL.ParseError) throws {
        let url = try #require(URL(string: raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw))
        #expect(throws: expected) { try ActivityURL.request(from: url) }
    }

    @Test func numberAcceptsFractionAndPercent() {
        #expect(ActivityRequest.number(from: "0.25") == 0.25)
        #expect(ActivityRequest.number(from: "25%") == 0.25)
        #expect(ActivityRequest.number(from: "çeyrek") == nil)
    }
}
