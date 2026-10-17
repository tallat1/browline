import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

struct ClaudeUsageTests {
    @Test func parsesScriptFormatAndStatuslineFormat() throws {
        let script = Data(#"{"captured_at":1760000000,"five_hour":{"used_percentage":42.4,"resets_at":1760007200},"seven_day":{"used_percentage":18}}"#.utf8)
        let usage = try #require(ClaudeUsageMonitor.parse(script, fallbackCapturedAt: .distantPast))
        #expect(usage.fiveHour == .init(usedPercentage: 42.4, resetsAt: Date(timeIntervalSince1970: 1760007200)))
        #expect(usage.sevenDay == .init(usedPercentage: 18, resetsAt: nil))
        #expect(usage.capturedAt == Date(timeIntervalSince1970: 1760000000))

        let statusline = Data(#"{"session_id":"x","rate_limits":{"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#.utf8)
        let fallback = Date(timeIntervalSince1970: 5)
        let second = try #require(ClaudeUsageMonitor.parse(statusline, fallbackCapturedAt: fallback))
        #expect(second.fiveHour == nil)
        #expect(second.sevenDay?.usedPercentage == 41.2)
        #expect(second.capturedAt == fallback)
        #expect(ClaudeUsageMonitor.parse(Data(#"{"session_id":"x"}"#.utf8), fallbackCapturedAt: fallback) == nil)
    }

    @Test func alertsOnlyWhenCrossingUp() {
        #expect(ClaudeUsageMonitor.crossedThreshold(from: 79, to: 81) == 80)
        #expect(ClaudeUsageMonitor.crossedThreshold(from: 70, to: 96) == 95)
        #expect(ClaudeUsageMonitor.crossedThreshold(from: 85, to: 90) == nil)
        #expect(ClaudeUsageMonitor.crossedThreshold(from: nil, to: 99) == nil)
    }
}

struct ClaudeAccountTests {
    @Test func parsesProfileWithoutSecrets() throws {
        let data = Data(#"{"userID":"x","oauthAccount":{"emailAddress":"ada@example.com","displayName":"Ada","organizationName":"Örnek AŞ","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_20x","profileFetchedAt":1760000000000}}"#.utf8)
        let account = try #require(ClaudeAccount.parse(data))
        #expect(account.email == "ada@example.com")
        #expect(account.displayName == "Ada")
        #expect(account.organizationName == "Örnek AŞ")
        #expect(account.plan == "Max 20x")
        #expect(account.fetchedAt == Date(timeIntervalSince1970: 1760000000))
        #expect(ClaudeAccount.parse(Data(#"{"userID":"x"}"#.utf8)) == nil)
        let personal = Data(#"{"oauthAccount":{"emailAddress":"ada@example.com","organizationName":"ada@example.com's Organization"}}"#.utf8)
        #expect(try #require(ClaudeAccount.parse(personal)).organizationName == nil)
    }

    @Test func planNames() {
        #expect(ClaudeAccount.planName(type: "claude_max", tier: "default_claude_max_5x") == "Max 5x")
        #expect(ClaudeAccount.planName(type: "claude_pro", tier: nil) == "Pro")
        #expect(ClaudeAccount.planName(type: "claude_team", tier: nil) == "Team")
        #expect(ClaudeAccount.planName(type: "something_else", tier: nil) == nil)
    }
}

struct ClaudeLimitLogTests {
    @Test func parsesRejectedLimitLines() throws {
        let line = #"{"type":"assistant","timestamp":"2026-10-08T23:18:33.004Z","apiErrorParams":{"rate_limit_info":{"status":"rejected","resetsAt":1791511800,"rateLimitType":"five_hour","overageStatus":"rejected","isUsingOverage":false}}}"#
        let hit = try #require(ClaudeLimitLog.parse(line: line))
        #expect(hit.type == "five_hour")
        #expect(hit.resetsAt == Date(timeIntervalSince1970: 1791511800))
        #expect(hit.hitAt != nil)
        #expect(!hit.isWeekly)
        let quota = #"{"quotaLimits":{"status":"rejected","resetsAt":1790847000,"rateLimitType":"seven_day_opus"}}"#
        let weekly = try #require(ClaudeLimitLog.parse(line: quota))
        #expect(weekly.isWeekly)
        #expect(weekly.modelSuffix == "Opus")
        #expect(ClaudeLimitLog.parse(line: #"{"quotaLimits":{"status":"allowed","resetsAt":1,"rateLimitType":"five_hour"}}"#) == nil)
    }

    @Test func activeHitsOnlyFutureAndLatestPerType() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("p"), withIntermediateDirectories: true)
        // Dosyanın değişme zamanı gerçek saat; "şimdi" de ona göre (7 günlük pencere).
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        let base = Int(now.timeIntervalSince1970)
        func line(_ type: String, _ offset: Int) -> String {
            #"{"apiErrorParams":{"rate_limit_info":{"status":"rejected","resetsAt":\#(base + offset),"rateLimitType":"\#(type)"}}}"#
        }
        let content = [line("five_hour", -1_000), line("five_hour", 3_600),
                       line("five_hour", 1_000), line("seven_day", 300_000), #"{"type":"user"}"#]
            .joined(separator: "\n")
        try content.write(to: directory.appendingPathComponent("p/a.jsonl"), atomically: true, encoding: .utf8)
        let hits = ClaudeLimitLog(directory: directory).activeHits(now: now)
        #expect(hits.map(\.type) == ["seven_day", "five_hour"])
        #expect(hits.last?.resetsAt == Date(timeIntervalSince1970: TimeInterval(base + 3_600)))
    }
}

struct ClaudeUsageProbeTests {
    let istanbul = TimeZone(identifier: "Europe/Istanbul")!
    var now: Date { date(2026, 10, 17, 18) }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = istanbul
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func parsesUsageOutput() throws {
        // ÖRNEK: Claude Code 2.1.220 `claude -p /usage` çıktısının biçimi (değerler örnek).
        let text = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 29% used · resets Oct 17 at 10:09pm (Europe/Istanbul)
        Current week (all models): 34% used · resets Oct 20 at 11:59am (Europe/Istanbul)
        Current week (Fable): 0% used · resets Oct 20 at 12pm (Europe/Istanbul)

        What's contributing to your limits usage?
        Last 24h · 787 requests · 5 sessions
          97% of your usage was at >150k context
        """
        let usage = try #require(ClaudeUsageProbe.parse(text, now: now))
        #expect(usage.fiveHour == .init(usedPercentage: 29, resetsAt: date(2026, 10, 17, 22, 9)))
        // Model başına satır ("Fable") tüm modellerin yerine geçmez; katkı satırlarındaki yüzdeler okunmaz.
        #expect(usage.sevenDay == .init(usedPercentage: 34, resetsAt: date(2026, 10, 20, 11, 59)))
        #expect(usage.capturedAt == now)
        #expect(usage.source == .claudeCode)
    }

    @Test func resetTimes() {
        #expect(ClaudeUsageProbe.resetDate("Oct 20 at 12pm (Europe/Istanbul)", now: now) == date(2026, 10, 20, 12))
        #expect(ClaudeUsageProbe.resetDate("Oct 18 at 12am (Europe/Istanbul)", now: now) == date(2026, 10, 18, 0))
        // Yalnız saat: geçtiyse yarın.
        #expect(ClaudeUsageProbe.resetDate("10pm (Europe/Istanbul)", now: now) == date(2026, 10, 17, 22))
        #expect(ClaudeUsageProbe.resetDate("9am (Europe/Istanbul)", now: now) == date(2026, 10, 18, 9))
        // Yıl yazılmıyor: Aralık sonunda Ocak tarihi gelecek yıl.
        let december = date(2026, 12, 30, 12)
        #expect(ClaudeUsageProbe.resetDate("Jan 2 at 9:30am (Europe/Istanbul)", now: december) == date(2027, 1, 2, 9, 30))
        #expect(ClaudeUsageProbe.resetDate("soon", now: now) == nil)
        #expect(ClaudeUsageProbe.resetDate("Oct 20 at 13pm (Europe/Istanbul)", now: now) == nil)
    }

    @Test func classifiesOutputWithoutLimits() {
        #expect(ClaudeUsageProbe.parse("Current week (Opus): 10% used", now: now) == nil)
        #expect(ClaudeUsageProbe.classify("Not logged in · Please run /login") == .signedOut)
        #expect(ClaudeUsageProbe.classify("You are currently using an API key") == .noSubscription)
        #expect(ClaudeUsageProbe.classify("Unknown command: /usage") == .unreadable)
    }

    @Test func newerSourceWins() {
        let probe = ClaudeUsageMonitor.Usage(fiveHour: .init(usedPercentage: 30, resetsAt: nil), sevenDay: nil,
                                             capturedAt: now, source: .claudeCode)
        var older = probe
        older.capturedAt = now.addingTimeInterval(-600)
        older.source = .statusline
        #expect(ClaudeUsageMonitor.shouldReplace(nil, with: older))
        #expect(!ClaudeUsageMonitor.shouldReplace(probe, with: older))
        #expect(ClaudeUsageMonitor.shouldReplace(older, with: probe))
        #expect(!ClaudeUsageMonitor.shouldReplace(probe, with: probe))
    }

    @Test func findsDesktopBundledClaudeNewestFirst() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("probe-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for version in ["2.1.9", "2.1.295"] {
            let binary = home.appendingPathComponent("Library/Application Support/Claude/claude-code/\(version)/abc/claude.app/Contents/MacOS/claude")
            try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: binary.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        }
        let found = ClaudeUsageProbe.desktopBundled(home: home, fileManager: .default)
        #expect(found.first?.path.contains("/2.1.295/") == true)
    }
}

struct ClaudeDecisionPresserTests {
    typealias Node = ClaudeDecisionPresser.Node

    private func text(_ value: String) -> Node { Node(role: "AXStaticText", text: value) }
    /// Electron'daki gibi: düğmenin adı çocuk metinde, birincil düğmede kısayol işaretleri.
    private func button(_ label: String, shortcut: Bool = false, id: String) -> Node {
        Node(role: "AXButton", text: "", children: [text(label)] + (shortcut ? [text("⌘"), text("↩")] : []), element: id as NSString)
    }

    private func box(ask: String, id: String) -> Node {
        Node(role: "AXGroup", text: "", children: [
            text("Recap metni."),
            Node(role: "AXGroup", text: "", children: [text(ask)]),
            Node(role: "AXGroup", text: "", children: [button("Evet, it", shortcut: true, id: "\(id)-1"), button("Şimdilik kalsın", id: "\(id)-2")]),
        ])
    }

    private func pressed(_ match: ClaudeDecisionPresser.Match) -> String? {
        if case .one(let node) = match { return node.element as? String }
        return nil
    }

    @Test func pressesOnlyTheBoxButton() {
        // Kutunun dışında aynı adlı bir düğme (ör. eski bir mesajdaki) yok sayılır.
        let page = Node(role: "AXWebArea", text: "", children: [
            Node(role: "AXGroup", text: "", children: [button("Evet, it", id: "outside")]),
            box(ask: "`35e1bb5` commit'ini origin/main'e iteyim mi?", id: "box"),
        ])
        let match = ClaudeDecisionPresser.match(in: [page], label: "Evet, it", ask: "35e1bb5 commit'ini origin/main'e iteyim mi?",
                                                options: ["Evet, it", "Şimdilik kalsın"])
        #expect(pressed(match) == "box-1")
        let second = ClaudeDecisionPresser.match(in: [page], label: "Şimdilik kalsın", ask: nil, options: ["Evet, it", "Şimdilik kalsın"])
        #expect(pressed(second) == "box-2")
    }

    @Test func refusesWhenUnsure() {
        let two = Node(role: "AXWebArea", text: "", children: [box(ask: "Push?", id: "a"), box(ask: "Push?", id: "b")])
        if case .many = ClaudeDecisionPresser.match(in: [two], label: "Evet, it", ask: "Push?", options: ["Evet, it"]) {} else {
            Issue.record("iki kutu: basılmamalı")
        }
        // Soru da diğer seçenekler de yoksa kutu tanınamaz.
        if case .none = ClaudeDecisionPresser.match(in: [two], label: "Evet, it", ask: nil, options: ["Evet, it"]) {} else {
            Issue.record("dayanak yok: basılmamalı")
        }
        // Kutu başka bir sorunun: yeni soru aranınca bulunmaz.
        if case .none = ClaudeDecisionPresser.match(in: [box(ask: "Eski soru?", id: "x")], label: "Evet, it", ask: "Yeni soru?", options: ["Evet, it"]) {} else {
            Issue.record("başka kutu: basılmamalı")
        }
    }

    @Test func normalizesShortcutGlyphsAndMarkdown() {
        #expect(ClaudeDecisionPresser.normalize("Evet,  uygula ⌘ ↩") == "evet, uygula")
        #expect(ClaudeDecisionPresser.normalize("`602efb2` **commit**'ini") == "602efb2 commit'ini")
    }
}
