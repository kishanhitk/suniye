import AppKit
import ApplicationServices
import XCTest
@testable import Suniye

final class TextInsertionServiceMoreTests: XCTestCase {
    // MARK: - InsertError

    func testInsertErrorDescribesEventCreationFailure() {
        XCTAssertEqual(
            TextInsertionService.InsertError.cannotCreateEvent.errorDescription,
            "Unable to generate keyboard event"
        )
        XCTAssertEqual(
            TextInsertionService.InsertError.cannotCreateEvent.localizedDescription,
            "Unable to generate keyboard event"
        )
        XCTAssertEqual(
            TextInsertionService.InsertError.cannotCopyToClipboard.localizedDescription,
            "Unable to copy transcription to the clipboard"
        )
        XCTAssertEqual(
            TextInsertionService.InsertError.insertionNotObserved.localizedDescription,
            "Text insertion was not observed in the focused field"
        )
    }

    // MARK: - captureInsertionContext guard paths

    func testCaptureInsertionContextReturnsNilWithoutFocusedElement() {
        let service = TextInsertionService()
        service.focusedTextElementProvider = { nil }

        XCTAssertNil(service.captureInsertionContext())
    }

    func testCaptureInsertionContextReturnsNilForOutOfBoundsSelection() {
        let service = TextInsertionService()
        service.focusedTextElementProvider = { AXUIElementCreateSystemWide() }
        service.focusedTextSnapshotProvider = { _ in
            TextInsertionService.FocusedTextSnapshot(
                value: "abc",
                selectedText: nil,
                selectedRange: NSRange(location: 10, length: 5)
            )
        }

        XCTAssertNil(service.captureInsertionContext())
    }

    // MARK: - makeFocusedFieldValueProvider

    func testFieldValueProviderIsNilWithoutFocusedElement() {
        let service = TextInsertionService()
        service.focusedTextElementProvider = { nil }

        XCTAssertNil(service.makeFocusedFieldValueProvider())
    }

    func testFieldValueProviderReReadsFieldAndReleasesService() throws {
        var service: TextInsertionService? = TextInsertionService()
        var fieldValue = "before edit"
        service?.focusedTextElementProvider = { AXUIElementCreateSystemWide() }
        service?.focusedTextSnapshotProvider = { _ in
            TextInsertionService.FocusedTextSnapshot(
                value: fieldValue,
                selectedText: nil,
                selectedRange: NSRange(location: 0, length: 0)
            )
        }

        let provider = try XCTUnwrap(service?.makeFocusedFieldValueProvider())
        XCTAssertEqual(provider(), "before edit")

        fieldValue = "after edit"
        XCTAssertEqual(provider(), "after edit")

        // The provider holds the service weakly; once released it reads nil.
        service = nil
        XCTAssertNil(provider())
    }

    // MARK: - Real focused-element lookup

    func testFocusedElementLookupReturnsNilWhenAccessibilityIsNotTrusted() {
        let service = TextInsertionService()
        service.accessibilityTrustProvider = { false }

        XCTAssertNil(service.captureInsertionContext())
    }

    func testFocusedElementLookupQueriesSystemWideElementWhenTrusted() {
        let service = TextInsertionService()
        service.accessibilityTrustProvider = { true }

        // Without a real trusted focused text field the system-wide lookup
        // fails and the context is nil; with trust granted it reads whatever
        // field is focused. Either way this must not crash or throw.
        _ = service.captureInsertionContext()
    }

    // MARK: - AX element helpers (fail paths are deterministic without permission)

    func testIsTextInputElementRejectsNonTextElements() {
        // System-wide element: role read fails outright.
        XCTAssertFalse(TextInsertionService.isTextInputElement(AXUIElementCreateSystemWide()))

        // Own application element: role reads as AXApplication when the AX
        // server answers, which is still not a text input.
        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        XCTAssertFalse(TextInsertionService.isTextInputElement(appElement))
    }

    func testSetSelectedTextReturnsFalseForUnsupportedElement() {
        let service = TextInsertionService()

        XCTAssertFalse(service.setSelectedText("hello", on: AXUIElementCreateSystemWide()))
    }

    func testCaptureFocusedTextStateReadsAllNilForUnsupportedElement() throws {
        let service = TextInsertionService()

        let state = try XCTUnwrap(service.captureFocusedTextState(for: AXUIElementCreateSystemWide()))
        XCTAssertNil(state.value)
        XCTAssertNil(state.selectedText)
        XCTAssertNil(state.selectedRange)
    }

    func testStringAttributeReturnsNilWhenAttributeIsUnsupported() {
        let service = TextInsertionService()

        XCTAssertNil(service.stringAttribute(kAXValueAttribute as CFString, from: AXUIElementCreateSystemWide()))
    }

    func testStringAttributeReadsRoleOfOwnApplicationElementWhenAvailable() {
        let service = TextInsertionService()
        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)

        // Same-process AX requests are only serviced when the app's AX server
        // can answer; when it does, the role must be AXApplication.
        if let role = service.stringAttribute(kAXRoleAttribute as CFString, from: appElement) {
            XCTAssertEqual(role, kAXApplicationRole as String)
        }
    }

    func testSelectedRangeAttributeReturnsNilWhenAttributeIsUnsupported() {
        let service = TextInsertionService()

        XCTAssertNil(service.selectedRangeAttribute(from: AXUIElementCreateSystemWide()))
    }

    // MARK: - Clipboard snapshot

    func testClipboardSnapshotSkipsTypesWithoutData() {
        let type = NSPasteboard.PasteboardType("dev.suniye.more.nil-data")
        let provider = NilPasteboardDataProvider()
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [type]))

        let snapshot = TextInsertionService.clipboardSnapshot(from: [item])

        XCTAssertEqual(snapshot.count, 1)
        XCTAssertTrue(snapshot[0].isEmpty)
    }

    // MARK: - virtualKeyCode

    func testVirtualKeyCodeReturnsNilForCharacterNotOnKeyboard() {
        XCTAssertNil(TextInsertionService.virtualKeyCode(for: "☃"))
    }

    // MARK: - DictationInsertionTextFormatter edge cases

    private func midSentenceContext() -> TextInsertionContext {
        TextInsertionContext(
            value: "coffeemachine",
            selectedRange: NSRange(location: 6, length: 0),
            selectedText: nil,
            previousCharacter: "e",
            nextCharacter: "m"
        )
    }

    func testFormatterLowercasesFirstWordAfterLeadingWhitespace() {
        let context = TextInsertionContext(
            value: "coffee",
            selectedRange: NSRange(location: 6, length: 0),
            selectedText: nil,
            previousCharacter: "e",
            nextCharacter: nil
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion(" Word", insertionContext: context),
            " word"
        )
    }

    func testFormatterKeepsEllipsisIntact() {
        // "..." has no first word to lowercase, and the final period is part of
        // an ellipsis so it must not be stripped.
        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("...", insertionContext: midSentenceContext()),
            "... "
        )
    }

    func testFormatterStripsFinalPeriodBeforeTrailingWhitespace() {
        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("Strong. ", insertionContext: midSentenceContext()),
            " strong "
        )
    }

    func testFormatterLeavesWhitespaceOnlyTextUnchanged() {
        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("   ", insertionContext: midSentenceContext()),
            "   "
        )
    }
}

private final class NilPasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        // Intentionally provide no data so data(forType:) returns nil.
    }
}
