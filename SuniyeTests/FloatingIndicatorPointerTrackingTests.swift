import XCTest
@testable import Suniye

final class FloatingIndicatorPointerTrackingTests: XCTestCase {
    func testTracksPointerScreenOnlyWhileIdleOrHovering() {
        XCTAssertTrue(FloatingIndicatorState.idle.tracksPointerScreen)
        XCTAssertTrue(FloatingIndicatorState.hover.tracksPointerScreen)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [], source: .manual).tracksPointerScreen)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [0.5], source: .editHotkey).tracksPointerScreen)
        XCTAssertFalse(FloatingIndicatorState.processing().tracksPointerScreen)
        XCTAssertFalse(FloatingIndicatorState.error(message: "Boom").tracksPointerScreen)
    }
}
