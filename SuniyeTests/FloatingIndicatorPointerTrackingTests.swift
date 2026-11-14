import XCTest
@testable import Suniye

final class FloatingIndicatorPointerTrackingTests: XCTestCase {
    func testIsAtRestOnlyWhileIdleOrHovering() {
        XCTAssertTrue(FloatingIndicatorState.idle.isAtRest)
        XCTAssertTrue(FloatingIndicatorState.hover.isAtRest)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [], source: .manual).isAtRest)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [0.5], source: .editHotkey).isAtRest)
        XCTAssertFalse(FloatingIndicatorState.processing().isAtRest)
        XCTAssertFalse(FloatingIndicatorState.error(message: "Boom").isAtRest)
    }

    func testOnlyHoverAndAPillStartedRecordingAcceptClicks() {
        XCTAssertTrue(FloatingIndicatorState.hover.acceptsClicks)
        XCTAssertTrue(FloatingIndicatorState.listening(levels: [], source: .manual).acceptsClicks)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [], source: .hotkey).acceptsClicks)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [], source: .editHotkey).acceptsClicks)
        XCTAssertFalse(FloatingIndicatorState.idle.acceptsClicks)
        XCTAssertFalse(FloatingIndicatorState.processing().acceptsClicks)
        XCTAssertFalse(FloatingIndicatorState.error(message: "Boom").acceptsClicks)
    }

    func testAMeetingTakesThePillOnlyAtRest() {
        XCTAssertTrue(FloatingIndicatorState.idle.showsMeetingPill(hasMeeting: true))
        XCTAssertTrue(FloatingIndicatorState.hover.showsMeetingPill(hasMeeting: true))
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [], source: .hotkey).showsMeetingPill(hasMeeting: true))
        XCTAssertFalse(FloatingIndicatorState.processing().showsMeetingPill(hasMeeting: true))
        XCTAssertFalse(FloatingIndicatorState.idle.showsMeetingPill(hasMeeting: false))
    }

    func testTheHoverHintShowsOnlyWithoutAMeeting() {
        XCTAssertTrue(FloatingIndicatorState.hover.showsHoverHint(hasMeeting: false))
        XCTAssertFalse(FloatingIndicatorState.hover.showsHoverHint(hasMeeting: true))
        XCTAssertFalse(FloatingIndicatorState.idle.showsHoverHint(hasMeeting: false))
    }
}
