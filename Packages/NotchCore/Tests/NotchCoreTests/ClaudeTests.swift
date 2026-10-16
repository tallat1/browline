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
