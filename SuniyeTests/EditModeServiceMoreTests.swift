import AppKit
import ApplicationServices
import XCTest
@testable import Suniye

@MainActor
final class EditModeServiceMoreTests: XCTestCase {
    func testCaptureErrorDescribesEventCreationFailure() {
        XCTAssertEqual(
            EditModeService.CaptureError.cannotCreateEvent.errorDescription,
            "Unable to generate keyboard event"
        )
        XCTAssertEqual(
            EditModeService.CaptureError.cannotCreateEvent.localizedDescription,
            "Unable to generate keyboard event"
        )
    }

    func testDefaultInitializerUsesRealCollaborators() {
        // Exercises the default arguments (AX trust check, system focused
        // element lookup, selected-text reader, general pasteboard) without
        // capturing anything, which would post real key events.
        _ = EditModeService()
    }

    func testSystemFocusedElementDoesNotCrashWithoutFocusedElement() {
        // Without a trusted, focused UI element this returns nil; with
        // Accessibility granted it may return whatever currently has focus.
        _ = EditModeService.systemFocusedElement()
    }

    func testSelectedTextAttributeReturnsNilForUnsupportedElement() {
        XCTAssertNil(EditModeService.selectedTextAttribute(of: AXUIElementCreateSystemWide()))
    }
}
