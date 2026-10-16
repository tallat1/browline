import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

struct SystemStatsTests {
    @Test func cpuUsageBetweenSamples() {
        let first = SystemStats.CPUTicks(busy: 100, total: 1000)
        #expect(SystemStats.cpuUsage(from: first, to: .init(busy: 150, total: 1100)) == 0.5)
        #expect(SystemStats.cpuUsage(from: nil, to: first) == nil)
        #expect(SystemStats.cpuUsage(from: first, to: first) == nil)
        // Kullanıcı ve sistem payı ayrı; toplamları meşgul oranı.
        let a = SystemStats.CPUTicks(user: 100, system: 50, busy: 150, total: 1000)
        let b = SystemStats.CPUTicks(user: 160, system: 70, busy: 230, total: 1200)
        let split = SystemStats.cpuSplit(from: a, to: b)
        #expect(split?.user == 0.3)
        #expect(split?.system == 0.1)
        #expect(SystemStats.cpuSplit(from: nil, to: b) == nil)
    }
}

struct SystemHistoryTests {
    @Test func historyKeepsTenMinutes() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = stride(from: 900.0, through: 0, by: -60).map {
            SystemStats.Sample(date: now.addingTimeInterval(-$0), cpuUser: 0.1, cpuSystem: 0.05, memory: 0.5,
                               download: 0, upload: 0)
        }
        let kept = SystemStats.trimmed(samples, now: now)
        #expect(kept.first?.date == now.addingTimeInterval(-600))
        #expect(kept.count == 11)
        #expect(SystemStats.trimmed([], now: now).isEmpty)
    }

    @Test func downsamplingKeepsEnds() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = (0..<600).map {
            SystemStats.Sample(date: now.addingTimeInterval(Double($0)), cpuUser: 0, cpuSystem: 0, memory: 0,
                               download: 0, upload: 0)
        }
        let drawn = SystemStats.downsampled(samples)
        #expect(drawn.count == 120)
        #expect(drawn.first == samples.first)
        #expect(drawn.last == samples.last)
        #expect(SystemStats.downsampled(Array(samples.prefix(50))).count == 50)
    }
}
