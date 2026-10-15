import Foundation

/// Pomodoro döngüsü: 25 dk odak, 5 dk mola; her dördüncü odaktan sonra 15 dk uzun mola.
/// Saf durum makinesi; zamanlamayı CountdownTimer yapar.
public enum Pomodoro {
    public enum Phase: Equatable, Sendable {
        /// 1'den başlar.
        case focus(round: Int)
        case shortBreak(afterRound: Int)
        case longBreak(afterRound: Int)

        public var isBreak: Bool {
            if case .focus = self { return false }
            return true
        }
    }

    public static let focusSeconds: TimeInterval = 25 * 60
    public static let shortBreakSeconds: TimeInterval = 5 * 60
    public static let longBreakSeconds: TimeInterval = 15 * 60
    public static let roundsBeforeLongBreak = 4

    public static let first = Phase.focus(round: 1)

    public static func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: focusSeconds
        case .shortBreak: shortBreakSeconds
        case .longBreak: longBreakSeconds
        }
    }

    public static func next(after phase: Phase) -> Phase {
        switch phase {
        case let .focus(round):
            round % roundsBeforeLongBreak == 0 ? .longBreak(afterRound: round) : .shortBreak(afterRound: round)
        case let .shortBreak(round), let .longBreak(round):
            .focus(round: round + 1)
        }
    }
}
