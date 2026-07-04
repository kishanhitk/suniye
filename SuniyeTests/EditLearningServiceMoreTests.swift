import AppKit
import XCTest
@testable import Suniye

@MainActor
final class EditLearningServiceMoreTests: XCTestCase {
    private final class TimerSpy {
        var scheduled: [(delay: TimeInterval, fire: @MainActor () -> Void)] = []
        var cancellations = 0

        @MainActor
        func schedule(_ delay: TimeInterval, _ handler: @escaping @MainActor () -> Void) -> () -> Void {
            scheduled.append((delay, handler))
            return { [weak self] in self?.cancellations += 1 }
        }

        @MainActor
        func fire(delay: TimeInterval) {
            for entry in scheduled where entry.delay == delay {
                entry.fire()
            }
        }
    }

    func testDefaultInitializerUsesRealCollaborators() {
        // Exercises the default arguments (spell checker, run-loop timers,
        // NSWorkspace notification center) without starting a session.
        let service = EditLearningService()
        service.finalizeActiveSession()
    }

    func testStopsLearningOnceSessionCapacityIsReached() {
        let timerSpy = TimerSpy()
        let service = EditLearningService(
            isKnownWord: { _ in false },
            scheduleTimer: { delay, handler in timerSpy.schedule(delay, handler) },
            workspaceNotificationCenter: NotificationCenter()
        )
        var learnedBatches: [[String]] = []
        service.onLearnedTerms = { learnedBatches.append($0) }

        let insertedText = "Aleks Borys Cyrus Dmitri"
        var fieldValue = insertedText
        service.beginTracking(EditLearningSession(
            insertedText: insertedText,
            fieldValueAfterInsertion: insertedText,
            existingVocabulary: [],
            readCurrentFieldValue: { fieldValue }
        ))

        // Three phonetically similar corrections exhaust the per-session cap.
        fieldValue = "Alekz Boris Cyros Dmitri"
        timerSpy.fire(delay: 10)
        XCTAssertEqual(learnedBatches, [["Alekz", "Boris", "Cyros"]])

        // A fourth correction is ignored because the capacity is exhausted.
        fieldValue = "Alekz Boris Cyros Dmitry"
        timerSpy.fire(delay: 30)
        XCTAssertEqual(learnedBatches, [["Alekz", "Boris", "Cyros"]])
    }

    func testSpellCheckerKnowsCommonWordsAndRejectsGibberish() {
        XCTAssertTrue(EditLearningService.spellCheckerKnowsWord("hello"))
        XCTAssertFalse(EditLearningService.spellCheckerKnowsWord("xqzjvvw"))
    }

    func testScheduleMainRunLoopTimerFiresHandlerOnMainActor() {
        let fired = expectation(description: "timer fired")
        let cancel = EditLearningService.scheduleMainRunLoopTimer(after: 0.01) {
            fired.fulfill()
        }

        wait(for: [fired], timeout: 2)
        // Cancelling after the timer fired is a harmless no-op.
        cancel()
    }

    func testScheduleMainRunLoopTimerCancelPreventsFiring() {
        var didFire = false
        let cancel = EditLearningService.scheduleMainRunLoopTimer(after: 0.05) {
            didFire = true
        }
        cancel()

        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertFalse(didFire)
    }
}
