import AppKit
import ApplicationServices
import XCTest
@testable import Suniye

final class TextInsertionServiceTests: XCTestCase {
    private enum TestError: Error {
        case keyPostFailed
    }

    func testClipboardSnapshotRoundTripsAllItemTypes() {
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("dev.suniye.test"))

        let snapshot = TextInsertionService.clipboardSnapshot(from: [item])
        let restored = TextInsertionService.pasteboardItems(from: snapshot)

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].string(forType: .string), "plain")
        XCTAssertEqual(restored[0].data(forType: NSPasteboard.PasteboardType("dev.suniye.test")), Data([1, 2, 3]))
    }

    func testCaptureInsertionContextReadsAdjacentCharacters() {
        let service = TextInsertionService()
        let element = AXUIElementCreateSystemWide()

        service.focusedTextElementProvider = { element }
        service.focusedTextSnapshotProvider = { _ in
            TextInsertionService.FocusedTextSnapshot(
                value: "coffeemachine",
                selectedText: nil,
                selectedRange: NSRange(location: 6, length: 0)
            )
        }

        let context = service.captureInsertionContext()

        XCTAssertEqual(context?.value, "coffeemachine")
        XCTAssertEqual(context?.selectedRange, NSRange(location: 6, length: 0))
        XCTAssertNil(context?.selectedText)
        XCTAssertEqual(context?.previousCharacter, "e")
        XCTAssertEqual(context?.nextCharacter, "m")
    }

    func testCaptureInsertionContextUsesSelectionEndForNextCharacter() {
        let service = TextInsertionService()
        let element = AXUIElementCreateSystemWide()

        service.focusedTextElementProvider = { element }
        service.focusedTextSnapshotProvider = { _ in
            TextInsertionService.FocusedTextSnapshot(
                value: "coffee machine",
                selectedText: "fee",
                selectedRange: NSRange(location: 3, length: 3)
            )
        }

        let context = service.captureInsertionContext()

        XCTAssertEqual(context?.previousCharacter, "f")
        XCTAssertEqual(context?.nextCharacter, " ")
        XCTAssertEqual(context?.selectedText, "fee")
    }

    func testInsertTextUsesVerifiedAccessibilityInsertionBeforeClipboardPaste() throws {
        let service = TextInsertionService()
        let element = AXUIElementCreateSystemWide()
        var state = TextInsertionService.FocusedTextSnapshot(value: "hello", selectedText: nil, selectedRange: NSRange(location: 5, length: 0))
        var insertedText: String?

        service.focusedTextElementProvider = { element }
        service.focusedTextSnapshotProvider = { _ in state }
        service.selectedTextSetter = { _, text in
            insertedText = text
            state = (value: "hello \(text)", selectedText: nil, selectedRange: NSRange(location: 11, length: 0))
            return true
        }
        service.keyPoster = { _, _ in
            XCTFail("Clipboard paste should not be used after verified AX insertion")
        }

        try service.insertText("world")

        XCTAssertEqual(insertedText, "world")
    }

    func testInsertTextFallsBackToClipboardPasteWhenAccessibilityInsertionIsNotVerified() throws {
        let service = TextInsertionService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)

        let element = AXUIElementCreateSystemWide()
        let unchanged = TextInsertionService.FocusedTextSnapshot(value: "hello", selectedText: nil, selectedRange: NSRange(location: 5, length: 0))
        var postedKeyCodes: [CGKeyCode] = []
        var postedFlags: [CGEventFlags] = []

        service.pasteboardProvider = { pasteboard }
        service.focusedTextElementProvider = { element }
        service.focusedTextSnapshotProvider = { _ in unchanged }
        service.selectedTextSetter = { _, _ in true }
        service.pasteKeyCodeProvider = { 42 }
        service.keyPoster = { keyCode, flags in
            postedKeyCodes.append(keyCode)
            postedFlags.append(flags)
        }

        try service.insertText("fallback")

        XCTAssertEqual(pasteboard.string(forType: .string), "fallback")
        XCTAssertEqual(postedKeyCodes, [42])
        XCTAssertEqual(postedFlags, [.maskCommand])
    }

    func testInsertTextStillRestoresClipboardWhenPasteKeyPostingThrows() throws {
        let service = TextInsertionService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)

        service.pasteboardProvider = { pasteboard }
        service.focusedTextElementProvider = { nil }
        service.pasteKeyCodeProvider = { 42 }
        service.clipboardRestoreDelay = 0
        service.keyPoster = { _, _ in
            throw TestError.keyPostFailed
        }

        XCTAssertThrowsError(try service.insertText("fallback")) { error in
            XCTAssertTrue(error is TestError)
        }

        let restored = expectation(description: "clipboard restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(pasteboard.string(forType: .string), "previous")
            restored.fulfill()
        }
        wait(for: [restored], timeout: 1)
    }

    func testSubmitActiveInputPostsReturnKey() throws {
        let service = TextInsertionService()
        var posted: [(CGKeyCode, CGEventFlags)] = []
        service.keyPoster = { keyCode, flags in
            posted.append((keyCode, flags))
        }

        try service.submitActiveInput()

        XCTAssertEqual(posted.count, 1)
        XCTAssertEqual(posted[0].0, 36)
        XCTAssertEqual(posted[0].1, [])
    }

    func testFormatterWithoutContextKeepsTextUnchanged() {
        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("Hello", insertionContext: nil),
            "Hello"
        )
    }

    func testFormatterAddsMissingSpacesBetweenWords() {
        let context = TextInsertionContext(
            value: "coffeemachine",
            selectedRange: NSRange(location: 6, length: 0),
            selectedText: nil,
            previousCharacter: "e",
            nextCharacter: "m"
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("strong", insertionContext: context),
            " strong "
        )
    }

    func testFormatterAvoidsDuplicateLeadingSpace() {
        let context = TextInsertionContext(
            value: "coffee machine",
            selectedRange: NSRange(location: 7, length: 0),
            selectedText: nil,
            previousCharacter: " ",
            nextCharacter: "m"
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("strong", insertionContext: context),
            "strong "
        )
    }

    func testFormatterDoesNotAddSpaceBeforePunctuation() {
        let context = TextInsertionContext(
            value: "Hello,",
            selectedRange: NSRange(location: 5, length: 0),
            selectedText: nil,
            previousCharacter: "o",
            nextCharacter: ","
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("friend", insertionContext: context),
            " friend"
        )
    }

    func testFormatterLowercasesTitlecaseFirstWordInMidSentence() {
        let context = TextInsertionContext(
            value: "The presentation will bemachine",
            selectedRange: NSRange(location: 24, length: 0),
            selectedText: nil,
            previousCharacter: "e",
            nextCharacter: "m"
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("Presented tomorrow", insertionContext: context),
            " presented tomorrow "
        )
    }

    func testFormatterDoesNotLowercaseAfterSentencePunctuation() {
        let context = TextInsertionContext(
            value: "Done.Next",
            selectedRange: NSRange(location: 5, length: 0),
            selectedText: nil,
            previousCharacter: ".",
            nextCharacter: "N"
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("Another item", insertionContext: context),
            " Another item "
        )
    }

    func testFormatterPreservesAcronymsAndCamelCase() {
        let acronymContext = TextInsertionContext(
            value: "we use",
            selectedRange: NSRange(location: 6, length: 0),
            selectedText: nil,
            previousCharacter: "e",
            nextCharacter: nil
        )
        let productContext = TextInsertionContext(
            value: "about",
            selectedRange: NSRange(location: 5, length: 0),
            selectedText: nil,
            previousCharacter: "t",
            nextCharacter: nil
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("NASA tools.", insertionContext: acronymContext),
            " NASA tools."
        )
        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("TypeWhisper", insertionContext: productContext),
            " TypeWhisper"
        )
    }

    func testFormatterStripsSingleFinalPeriodBeforeExistingWord() {
        let context = TextInsertionContext(
            value: "coffeemachine",
            selectedRange: NSRange(location: 6, length: 0),
            selectedText: nil,
            previousCharacter: "e",
            nextCharacter: "m"
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("Strong.", insertionContext: context),
            " strong "
        )
    }

    func testFormatterPreservesQuestionPunctuation() {
        let context = TextInsertionContext(
            value: "coffeemachine",
            selectedRange: NSRange(location: 6, length: 0),
            selectedText: nil,
            previousCharacter: "e",
            nextCharacter: "m"
        )

        XCTAssertEqual(
            DictationInsertionTextFormatter.textForInsertion("Really?", insertionContext: context),
            " really? "
        )
    }
}
