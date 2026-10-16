import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

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

struct PomodoroTests {
    @Test func cycleWithLongBreakEveryFourthRound() {
        var phase = Pomodoro.first
        var seen: [Pomodoro.Phase] = [phase]
        for _ in 0..<8 {
            phase = Pomodoro.next(after: phase)
            seen.append(phase)
        }
        #expect(seen == [.focus(round: 1), .shortBreak(afterRound: 1), .focus(round: 2), .shortBreak(afterRound: 2),
                         .focus(round: 3), .shortBreak(afterRound: 3), .focus(round: 4), .longBreak(afterRound: 4),
                         .focus(round: 5)])
        #expect(Pomodoro.duration(of: .longBreak(afterRound: 4)) == 15 * 60)
        #expect(Pomodoro.Phase.shortBreak(afterRound: 1).isBreak)
    }
}
