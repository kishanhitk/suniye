import XCTest
@testable import Suniye

final class DictationShortcutGestureTests: XCTestCase {
    private let firstPress = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ milliseconds: Int) -> Date {
        firstPress.addingTimeInterval(Double(milliseconds) / 1_000)
    }

    func testHoldFinishesOnRelease() {
        var gesture = DictationShortcutGesture()

        XCTAssertEqual(gesture.press(at: at(0)), .start)
        XCTAssertEqual(gesture.release(at: at(1_800), canLock: true), .finish)
    }

    func testPressOf300MillisecondsIsAHoldAndShorterIsATap() {
        var hold = DictationShortcutGesture()
        _ = hold.press(at: at(0))
        XCTAssertEqual(hold.release(at: at(300), canLock: true), .finish)

        var tap = DictationShortcutGesture()
        _ = tap.press(at: at(0))
        XCTAssertEqual(tap.release(at: at(299), canLock: true), .waitForSecondTap)
    }

    func testSingleTapIsDiscardedWhenNoSecondTapComes() {
        var gesture = DictationShortcutGesture()
        _ = gesture.press(at: at(0))

        XCTAssertEqual(gesture.release(at: at(120), canLock: true), .waitForSecondTap)
        XCTAssertEqual(gesture.secondTapWindowEnded(), .discard)
        XCTAssertEqual(gesture.press(at: at(500)), .start, "the next press starts a new recording")
    }

    func testDoubleTapLocksAndTheNextPressFinishesOnItsRelease() {
        var gesture = DictationShortcutGesture()
        _ = gesture.press(at: at(0))
        _ = gesture.release(at: at(120), canLock: true)

        XCTAssertNil(gesture.press(at: at(260)))
        XCTAssertEqual(gesture.release(at: at(380), canLock: true), .lock)
        XCTAssertTrue(gesture.isLocked)
        XCTAssertNil(gesture.secondTapWindowEnded(), "a late window end must not drop a locked recording")

        XCTAssertNil(gesture.press(at: at(9_000)), "the finishing press waits for its release")
        XCTAssertFalse(gesture.isLocked)
        XCTAssertEqual(gesture.release(at: at(9_100), canLock: true), .finish)
    }

    func testTapThenHoldFinishesOnTheSecondRelease() {
        var gesture = DictationShortcutGesture()
        _ = gesture.press(at: at(0))
        _ = gesture.release(at: at(120), canLock: true)
        _ = gesture.press(at: at(260))

        XCTAssertEqual(gesture.release(at: at(1_900), canLock: true), .finish)
        XCTAssertFalse(gesture.isLocked)
    }

    func testTapIsDiscardedAtOnceWhenTheShortcutCannotLock() {
        var gesture = DictationShortcutGesture()
        _ = gesture.press(at: at(0))

        XCTAssertEqual(gesture.release(at: at(120), canLock: false), .discard)
        XCTAssertEqual(gesture.press(at: at(260)), .start)
    }

    func testShortPressWithAnotherKeyIsDiscardedAtOnce() {
        var gesture = DictationShortcutGesture()
        _ = gesture.press(at: at(0))
        gesture.markChord()

        XCTAssertEqual(gesture.release(at: at(150), canLock: true), .discard, "fn+Delete is typing, not a tap")
    }

    func testChordAsTheSecondPressDoesNotLock() {
        var gesture = DictationShortcutGesture()
        _ = gesture.press(at: at(0))
        _ = gesture.release(at: at(120), canLock: true)
        _ = gesture.press(at: at(250))
        gesture.markChord()

        XCTAssertEqual(gesture.release(at: at(380), canLock: true), .discard)
        XCTAssertFalse(gesture.isLocked)
    }

    func testChordWhileLockedKeepsTheLock() {
        var gesture = DictationShortcutGesture()
        _ = gesture.press(at: at(0))
        _ = gesture.release(at: at(120), canLock: true)
        _ = gesture.press(at: at(260))
        _ = gesture.release(at: at(380), canLock: true)

        _ = gesture.press(at: at(5_000))
        gesture.markChord()

        XCTAssertNil(gesture.release(at: at(5_100), canLock: true), "fn+arrow while locked must not finish")
        XCTAssertTrue(gesture.isLocked)
    }

    func testLongHoldWithAnotherKeyStillFinishes() {
        var gesture = DictationShortcutGesture()
        _ = gesture.press(at: at(0))
        gesture.markChord()

        XCTAssertEqual(gesture.release(at: at(2_000), canLock: true), .finish, "a hold works as today")
    }
}
