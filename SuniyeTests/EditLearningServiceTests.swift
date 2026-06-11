import AppKit
import XCTest
@testable import Suniye

@MainActor
final class EditLearningServiceTests: XCTestCase {
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

    private var timerSpy: TimerSpy!
    private var notificationCenter: NotificationCenter!
    private var service: EditLearningService!
    private var learnedBatches: [[String]] = []
    private var fieldValue: String?

    override func setUp() {
        super.setUp()
        timerSpy = TimerSpy()
        notificationCenter = NotificationCenter()
        learnedBatches = []
        fieldValue = nil
        let timerSpy = timerSpy!
        service = EditLearningService(
            isKnownWord: { ["lunch", "with", "at", "noon", "the"].contains($0.lowercased()) },
            scheduleTimer: { delay, handler in timerSpy.schedule(delay, handler) },
            workspaceNotificationCenter: notificationCenter
        )
        service.onLearnedTerms = { [weak self] terms in
            self?.learnedBatches.append(terms)
        }
    }

    private func beginTracking(
        insertedText: String = "Lunch with Keshawn at noon.",
        fieldValueAfterInsertion: String? = "Lunch with Keshawn at noon.",
        existingVocabulary: [String] = []
    ) {
        fieldValue = fieldValueAfterInsertion
        service.beginTracking(EditLearningSession(
            insertedText: insertedText,
            fieldValueAfterInsertion: fieldValueAfterInsertion,
            existingVocabulary: existingVocabulary,
            readCurrentFieldValue: { [weak self] in self?.fieldValue }
        ))
    }

    func testLearnsCorrectionAtFirstCheckpoint() {
        beginTracking()
        fieldValue = "Lunch with Kishan at noon."

        timerSpy.fire(delay: 10)

        XCTAssertEqual(learnedBatches, [["Kishan"]])
    }

    func testNoCallbackWhenNothingChanges() {
        beginTracking()

        timerSpy.fire(delay: 10)
        timerSpy.fire(delay: 30)
        timerSpy.fire(delay: 60)

        XCTAssertEqual(learnedBatches, [])
    }

    func testDoesNotLearnSameTermTwiceAcrossCheckpoints() {
        beginTracking()
        fieldValue = "Lunch with Kishan at noon."

        timerSpy.fire(delay: 10)
        timerSpy.fire(delay: 30)

        XCTAssertEqual(learnedBatches, [["Kishan"]])
    }

    func testFinalizeLearnsImmediatelyAndEndsSession() {
        beginTracking()
        fieldValue = "Lunch with Kishan at noon."

        service.finalizeActiveSession()

        XCTAssertEqual(learnedBatches, [["Kishan"]])
        XCTAssertEqual(timerSpy.cancellations, 3)

        fieldValue = "Lunch with Ananya at noon."
        timerSpy.fire(delay: 10)
        timerSpy.fire(delay: 30)
        timerSpy.fire(delay: 60)
        XCTAssertEqual(learnedBatches, [["Kishan"]])
    }

    func testAppSwitchFinalizesSession() {
        beginTracking()
        fieldValue = "Lunch with Kishan at noon."

        notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

        XCTAssertEqual(learnedBatches, [["Kishan"]])

        fieldValue = "Lunch with Ananya at noon."
        notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertEqual(learnedBatches, [["Kishan"]])
    }

    func testEstablishesBaselineLateWhenPasteArrivesAfterSnapshot() {
        // Clipboard paste lands asynchronously: the post-insertion snapshot misses the text.
        beginTracking(fieldValueAfterInsertion: "")
        fieldValue = "Lunch with Keshawn at noon."

        timerSpy.fire(delay: 10)
        XCTAssertEqual(learnedBatches, [])

        fieldValue = "Lunch with Kishan at noon."
        timerSpy.fire(delay: 30)

        XCTAssertEqual(learnedBatches, [["Kishan"]])
    }

    func testNilReadIsIgnoredUntilLaterCheckpoint() {
        beginTracking()
        fieldValue = nil

        timerSpy.fire(delay: 10)
        XCTAssertEqual(learnedBatches, [])

        fieldValue = "Lunch with Kishan at noon."
        timerSpy.fire(delay: 30)

        XCTAssertEqual(learnedBatches, [["Kishan"]])
    }

    func testSessionEndsAtFinalCheckpoint() {
        beginTracking()

        timerSpy.fire(delay: 60)

        fieldValue = "Lunch with Kishan at noon."
        timerSpy.fire(delay: 10)
        notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

        XCTAssertEqual(learnedBatches, [])
    }

    func testBeginTrackingFinalizesPreviousSession() {
        beginTracking()
        fieldValue = "Lunch with Kishan at noon."

        // The next dictation targets a different field; the first session's
        // reader still sees the edited text when it is finalized.
        service.beginTracking(EditLearningSession(
            insertedText: "Ship it today.",
            fieldValueAfterInsertion: "Ship it today.",
            existingVocabulary: [],
            readCurrentFieldValue: { "Ship it today." }
        ))

        XCTAssertEqual(learnedBatches, [["Kishan"]])
    }

    func testRespectsExistingVocabulary() {
        beginTracking(existingVocabulary: ["Kishan"])
        fieldValue = "Lunch with Kishan at noon."

        timerSpy.fire(delay: 10)

        XCTAssertEqual(learnedBatches, [])
    }
}
