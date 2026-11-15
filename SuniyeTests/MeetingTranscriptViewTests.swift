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
    private var textView: MeetingTranscriptTextView!
    private var coordinator: MeetingTranscriptView.Coordinator!
    private var reports: [(texts: [UUID: String], ended: Bool)] = []

    private var lines: [MeetingTranscriptLine] {
        [
            MeetingTranscriptLine(id: first, time: "00:00", speaker: .them, text: "Did the build pass?"),
            MeetingTranscriptLine(id: second, time: "00:04", speaker: .you, text: "It did."),
        ]
    }

    override func setUp() async throws {
        coordinator = MeetingTranscriptView.Coordinator()
        coordinator.edited = { [weak self] texts, ended in self?.reports.append((texts, ended)) }
        scrollView = MeetingTranscriptView.scrollView()
        textView = try XCTUnwrap(scrollView.documentView as? MeetingTranscriptTextView)
        coordinator.attach(to: textView)
        textView.isEditable = true
        coordinator.render(lines, canSeek: false, into: textView)
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

    func testAClickOnATimePlaysFromItsLine() throws {
        var played: [UUID] = []
        coordinator.seek = { played.append($0) }
        coordinator.render(lines, canSeek: true, into: textView)
        let time = (textView.string as NSString).range(of: "00:04")
        let link = try XCTUnwrap(textView.textStorage?.attribute(.link, at: time.location, effectiveRange: nil))

        textView.clicked(onLink: link, at: time.location)

        XCTAssertEqual(played, [second])
    }

    func testTimesThatBecomeLinksKeepAnEditThatWaitsForItsSave() throws {
        select("pass")
        type("ship")
        let edited = [
            MeetingTranscriptLine(id: first, time: "00:00", speaker: .them, text: "Did the build ship?"),
            MeetingTranscriptLine(id: second, time: "00:04", speaker: .you, text: "It did."),
        ]

        coordinator.render(edited, canSeek: true, into: textView)
        select("did")
        type("does")

        XCTAssertEqual(reports.last?.texts, [first: "Did the build ship?", second: "It does."], "the save of the first edit has not run")
        XCTAssertNotNil(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil))
        XCTAssertEqual(try XCTUnwrap(textView.undoManager).canUndo, true)
    }

    func testAMarkedLineStaysMarkedWhenALineAboveItChanges() {
        coordinator.mark([second], follow: 1, in: textView)

        select("pass")
        type("pass with every test on the release branch")

        let string = textView.string as NSString
        XCTAssertEqual(textView.marked, [string.paragraphRange(for: string.range(of: "It did."))])
        XCTAssertEqual(textView.bands(layingOut: true).map(\.width), [textView.bounds.width], "the band spans the row")
    }

    func testTheViewFollowsTheMarkedLineUntilTheUserScrolls() {
        let many = (0 ..< 80).map { MeetingTranscriptLine(id: UUID(), time: String(format: "00:%02d", $0 % 60), speaker: .you, text: "Line \($0).") }
        coordinator.render(many, canSeek: true, into: textView)

        coordinator.mark([many[70].id], follow: 1, in: textView)
        let followed = scrollView.documentVisibleRect.minY
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        textView.scroll(.zero)
        coordinator.mark([many[75].id], follow: 1, in: textView)
        let afterTheUserScrolled = scrollView.documentVisibleRect.minY
        coordinator.mark([many[75].id], follow: 2, in: textView)
        let afterANewStart = scrollView.documentVisibleRect.minY

        XCTAssertGreaterThan(followed, 0)
        XCTAssertEqual(afterTheUserScrolled, 0)
        XCTAssertGreaterThan(afterANewStart, 0)
    }

    func testTheViewScrollsToTheRealPlaceOfAFarLineBelowLongLines() throws {
        let words = String(repeating: "A line long enough to wrap to more than one row in the view. ", count: 3)
        let many = (0 ..< 80).map { MeetingTranscriptLine(id: UUID(), time: "00:00", speaker: .you, text: "\($0). \(words)") }
        coordinator.render(many, canSeek: true, into: textView)

        coordinator.mark([many[70].id], follow: 1, in: textView)

        let layoutManager = try XCTUnwrap(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let band = try XCTUnwrap(textView.bands(layingOut: false).first)
        XCTAssertTrue(scrollView.documentVisibleRect.contains(band), "\(band) in \(scrollView.documentVisibleRect)")
    }

    func testANewTranscriptIsDrawnAndTheEditedOneIsNot() {
        select("pass")
        type("ship")
        let edited = [
            MeetingTranscriptLine(id: first, time: "00:00", speaker: .them, text: "Did the build ship?"),
            MeetingTranscriptLine(id: second, time: "00:04", speaker: .you, text: "It did."),
        ]
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        coordinator.render(edited, canSeek: false, into: textView)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0), "the lines that the page got back from the edit draw nothing")

        coordinator.render([MeetingTranscriptLine(id: UUID(), time: "00:00", speaker: .them, text: "New words.")], canSeek: false, into: textView)

        XCTAssertEqual(textView.string, "00:00\tThem\tNew words.\n")
    }
}
