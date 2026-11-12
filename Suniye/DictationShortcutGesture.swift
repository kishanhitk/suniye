import Foundation

/// Reads presses of the dictation shortcut. A hold records until release. Two
/// taps lock the recording, and the next press finishes it. The recording
/// starts on the first press in every case, so a double tap loses no audio.
/// A press with another key in it (fn+Delete) is typing: it is never a tap,
/// never locks, and never finishes a lock.
struct DictationShortcutGesture {
    /// A press shorter than this is a tap. The second tap of a double tap must
    /// start within this time of the first release.
    static let tapInterval: TimeInterval = 0.3

    enum ReleaseCommand: Equatable {
        case finish
        case discard
        case waitForSecondTap
        case lock
    }

    private struct Press: Equatable {
        let since: Date
        var isChord = false

        func isHold(releasedAt time: Date) -> Bool {
            time.timeIntervalSince(since) >= DictationShortcutGesture.tapInterval
        }
    }

    private enum State: Equatable {
        case idle
        case firstPress(Press)
        case waitingForSecondTap
        case secondPress(Press)
        case locked
        case finishingPress(isChord: Bool)
    }

    private var state: State = .idle

    var isLocked: Bool {
        state == .locked
    }

    /// Returns true when the press starts a new recording.
    mutating func press(at time: Date) -> Bool {
        switch state {
        case .idle:
            state = .firstPress(Press(since: time))
            return true
        case .waitingForSecondTap:
            state = .secondPress(Press(since: time))
        case .locked:
            state = .finishingPress(isChord: false)
        case .firstPress, .secondPress, .finishingPress:
            break
        }
        return false
    }

    mutating func markChord() {
        switch state {
        case var .firstPress(press):
            press.isChord = true
            state = .firstPress(press)
        case var .secondPress(press):
            press.isChord = true
            state = .secondPress(press)
        case .finishingPress:
            state = .finishingPress(isChord: true)
        case .idle, .waitingForSecondTap, .locked:
            break
        }
    }

    /// `canLock` is read only for a first tap. It is false when a Globe tap
    /// also runs a macOS action.
    mutating func release(at time: Date, canLock: () -> Bool) -> ReleaseCommand? {
        switch state {
        case let .firstPress(press):
            if press.isHold(releasedAt: time) {
                state = .idle
                return .finish
            }
            guard !press.isChord, canLock() else {
                state = .idle
                return .discard
            }
            state = .waitingForSecondTap
            return .waitForSecondTap
        case let .secondPress(press):
            if press.isHold(releasedAt: time) {
                state = .idle
                return .finish
            }
            guard !press.isChord else {
                state = .idle
                return .discard
            }
            state = .locked
            return .lock
        case let .finishingPress(isChord):
            guard !isChord else {
                state = .locked
                return nil
            }
            state = .idle
            return .finish
        case .idle, .waitingForSecondTap, .locked:
            return nil
        }
    }

    /// Returns true when the recording waited for a second tap that did not come.
    mutating func secondTapWindowEnded() -> Bool {
        guard state == .waitingForSecondTap else {
            return false
        }
        state = .idle
        return true
    }

    mutating func reset() {
        state = .idle
    }
}
