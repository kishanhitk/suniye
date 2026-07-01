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

    func testInsertTextPrefersVerifiedAXOverTypeOut() throws {
        let service = TextInsertionService()
        let element = AXUIElementCreateSystemWide()
        var state = TextInsertionService.FocusedTextSnapshot(value: "hi", selectedText: nil, selectedRange: NSRange(location: 2, length: 0))

        service.secureFieldDetector = { false }
        service.focusedTextElementProvider = { element }
        service.focusedTextSnapshotProvider = { _ in state }
        service.selectedTextSetter = { _, text in
            state = (value: "hi \(text)", selectedText: nil, selectedRange: NSRange(location: 5, length: 0))
            return true
        }
        service.insertionStrategyProvider = { .keyboardTypeOut }
        service.unicodeTyper = { _ in XCTFail("Type-out must not run when AX insertion is verified") }
        service.keyPoster = { _, _ in XCTFail("Paste must not run when AX insertion is verified") }

        try service.insertText("there")
    }

    func testTypeOutFiresWhenAXFailsAndStrategyIsTypeOut() throws {
        let service = TextInsertionService()
        var typed: [String] = []

        service.secureFieldDetector = { false }
        service.focusedTextElementProvider = { nil }
        service.insertionStrategyProvider = { .keyboardTypeOut }
        service.unicodeTyper = { typed.append($0) }
        service.keyPoster = { _, _ in XCTFail("Paste must not run under the type-out strategy") }

        try service.insertText("héllo 👍")

        XCTAssertEqual(typed, ["héllo 👍"])
    }

    func testUnicodeChunksDoNotSplitSurrogatePairs() {
        let input = "Hi 👍!"
        let chunks = TextInsertionService.unicodeChunks(for: input, maxChunkUTF16: 2)

        // A split surrogate pair would decode to U+FFFD, so exact reconstruction proves no split.
        let reconstructed = chunks.map { String(utf16CodeUnits: $0, count: $0.count) }.joined()
        XCTAssertEqual(reconstructed, input, "chunking must not split a grapheme / surrogate pair")
        XCTAssertTrue(chunks.contains { String(utf16CodeUnits: $0, count: $0.count).contains("👍") })
    }

    func testClipboardRestoreSkippedWhenUserChangedClipboard() throws {
        let service = TextInsertionService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)

        service.secureFieldDetector = { false }
        service.pasteboardProvider = { pasteboard }
        service.focusedTextElementProvider = { nil }
        service.pasteKeyCodeProvider = { 42 }
        service.clipboardRestoreDelay = 0.1
        service.keyPoster = { _, _ in }

        try service.insertText("fallback")
        // User copies during the restore window → changeCount bumps → restore must skip.
        pasteboard.clearContents()
        pasteboard.setString("user copied this", forType: .string)

        let checked = expectation(description: "restore window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            XCTAssertEqual(pasteboard.string(forType: .string), "user copied this")
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
    }

    func testClipboardRestoreProceedsWhenChangeCountUnchanged() throws {
        let service = TextInsertionService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)

        service.secureFieldDetector = { false }
        service.pasteboardProvider = { pasteboard }
        service.focusedTextElementProvider = { nil }
        service.pasteKeyCodeProvider = { 42 }
        service.clipboardRestoreDelay = 0.05
        service.keyPoster = { _, _ in } // paste only reads; no changeCount bump

        try service.insertText("fallback")

        let restored = expectation(description: "clipboard restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(pasteboard.string(forType: .string), "previous")
            restored.fulfill()
        }
        wait(for: [restored], timeout: 1)
    }

    func testSecureFieldIsNeverTypedOrPasted() throws {
        let service = TextInsertionService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)

        service.secureFieldDetector = { true }
        service.pasteboardProvider = { pasteboard }
        service.insertionStrategyProvider = { .keyboardTypeOut }
        service.unicodeTyper = { _ in XCTFail("Must not type into a secure field") }
        service.selectedTextSetter = { _, _ in XCTFail("Must not AX-write into a secure field"); return false }
        service.keyPoster = { _, _ in XCTFail("Must not paste into a secure field") }

        XCTAssertThrowsError(try service.insertText("hunter2")) { error in
            XCTAssertEqual(error as? TextInsertionService.InsertError, .secureFieldUnsupported)
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
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
