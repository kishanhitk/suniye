import XCTest
@testable import Suniye

final class FloatingIndicatorPointerTrackingTests: XCTestCase {
    func testTracksPointerScreenOnlyWhileIdleOrHovering() {
        XCTAssertTrue(FloatingIndicatorState.idle.isAtRest)
        XCTAssertTrue(FloatingIndicatorState.hover.isAtRest)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [], source: .manual).isAtRest)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [0.5], source: .editHotkey).isAtRest)
        XCTAssertFalse(FloatingIndicatorState.processing().isAtRest)
        XCTAssertFalse(FloatingIndicatorState.error(message: "Boom").isAtRest)
    }
}
