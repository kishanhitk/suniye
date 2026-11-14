import AppKit
import XCTest
@testable import Suniye

/// Drives the transcript through its real text view, in a window that never
/// shows.
@MainActor
final class MeetingTranscriptViewTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()
    private var window: NSWindow!
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var coordinator: MeetingTranscriptView.Coordinator!
    private var reports: [(texts: [UUID: String], ended: Bool)] = []

    override func setUp() async throws {
        coordinator = MeetingTranscriptView.Coordinator()
        coordinator.edited = { [weak self] texts, ended in self?.reports.append((texts, ended)) }
        scrollView = MeetingTextView.scrollable()
        textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        coordinator.attach(to: textView)
        textView.isEditable = true
        coordinator.render([
            MeetingTranscriptLine(id: first, time: "00:00", speaker: .them, text: "Did the build pass?"),
            MeetingTranscriptLine(id: second, time: "00:04", speaker: .you, text: "It did."),
        ], into: textView)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        scrollView.frame = window.contentView!.bounds
        window.contentView?.addSubview(scrollView)
        XCTAssertTrue(window.makeFirstResponder(textView))
    }

    override func tearDown() async throws {
        window.close()
    }

    private func select(_ text: String) {
        let range = (textView.string as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, text)
        textView.setSelectedRange(range)
    }

    private func type(_ text: String) {
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    func testTypingInALineChangesOnlyThatLine() {
        select("pass")
        type("ship")

        XCTAssertEqual(reports.last?.texts, [first: "Did the build ship?"])
        XCTAssertEqual(reports.last?.ended, false)
    }

    func testTheTimeAndTheSpeakerCannotChange() {
        let before = textView.string
        select("00:04")
        type("9")
        select("You")
        type("Me")

        XCTAssertEqual(textView.string, before)
        XCTAssertTrue(reports.isEmpty)
    }

    func testAChangeOverTwoLinesIsRefused() {
        let before = textView.string
        select("pass?\n00:04\tYou\tIt")
        type("x")

        XCTAssertEqual(textView.string, before)
        XCTAssertTrue(reports.isEmpty)
    }

    func testReturnEndsTheEditAndMakesNoNewLine() {
        select("did")
        type("does")
        let lines = textView.string.components(separatedBy: "\n").count

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(textView.string.components(separatedBy: "\n").count, lines)
        XCTAssertFalse(window.firstResponder === textView)
        XCTAssertEqual(reports.last?.texts, [second: "It does."])
        XCTAssertEqual(reports.last?.ended, true)
    }

    func testPastedLinesBecomeOneLine() {
        select("It did.")
        type("Yes.\nIt did.")

        XCTAssertEqual(reports.last?.texts, [second: "Yes. It did."])
    }

    func testAnEmptiedLineIsKeptUntilTheEditEnds() {
        select("It did.")
        textView.deleteBackward(nil)

        XCTAssertEqual(reports.last?.texts, [second: ""])
        XCTAssertEqual(reports.last?.ended, false)
        XCTAssertTrue(textView.string.contains("00:04\tYou\t\n"))

        window.makeFirstResponder(nil)

        XCTAssertEqual(reports.last?.texts, [second: ""])
        XCTAssertEqual(reports.last?.ended, true)
    }

    func testTypedTextTakesTheLineStyleAtTheStartOfALine() throws {
        let start = (textView.string as NSString).range(of: "It did.").location
        textView.setSelectedRange(NSRange(location: start, length: 0))
        type("Yes. ")

        let font = try XCTUnwrap(textView.textStorage?.attribute(.font, at: start, effectiveRange: nil) as? NSFont)
        let color = textView.textStorage?.attribute(.foregroundColor, at: start, effectiveRange: nil) as? NSColor
        XCTAssertEqual(font, NSFont.preferredFont(forTextStyle: .body))
        XCTAssertEqual(color, NSColor.labelColor)
    }

    func testUndoReportsTheOldTextSoTheSaveRestoresIt() throws {
        select("pass")
        type("ship")
        textView.breakUndoCoalescing()

        try XCTUnwrap(textView.undoManager).undo()

        XCTAssertEqual(reports.last?.texts, [first: "Did the build pass?"])
    }

    func testLeavingThePageEndsTheEdit() {
        select("It did.")
        textView.deleteBackward(nil)

        scrollView.removeFromSuperview()

        XCTAssertEqual(reports.last?.ended, true)
    }

    func testANewTranscriptIsDrawnAndTheEditedOneIsNot() {
        select("pass")
        type("ship")
        let edited = [
            MeetingTranscriptLine(id: first, time: "00:00", speaker: .them, text: "Did the build ship?"),
            MeetingTranscriptLine(id: second, time: "00:04", speaker: .you, text: "It did."),
        ]
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        coordinator.render(edited, into: textView)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0), "the lines that the page got back from the edit draw nothing")

        coordinator.render([MeetingTranscriptLine(id: UUID(), time: "00:00", speaker: .them, text: "New words.")], into: textView)

        XCTAssertEqual(textView.string, "00:00\tThem\tNew words.\n")
    }
}
