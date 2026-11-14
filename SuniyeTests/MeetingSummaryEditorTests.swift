import AppKit
import XCTest
@testable import Suniye

/// Drives the summary through its real text view, in a window that never
/// shows.
@MainActor
final class MeetingSummaryEditorTests: XCTestCase {
    private let summary = """
    ## Overview
    The team reviewed the release.
    ## Decisions
    - Ship on Thursday.
    - Keep the old onboarding.
    """
    private var window: NSWindow!
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var coordinator: MeetingSummaryEditor.Coordinator!
    private var reports: [(markdown: String, ended: Bool)] = []

    override func setUp() async throws {
        coordinator = MeetingSummaryEditor.Coordinator()
        coordinator.edited = { [weak self] markdown, ended in self?.reports.append((markdown, ended)) }
        scrollView = MeetingTextView.scrollable(textKit2: false)
        textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        coordinator.attach(to: textView)
        textView.isEditable = true
        coordinator.render(summary, into: textView)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
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

    private func caret(after text: String) {
        let range = (textView.string as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, text)
        textView.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
    }

    private func type(_ text: String) {
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    func testTheMarkdownComesBackAsItWent() throws {
        let storage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(MeetingSummaryEditor.Style.markdown(from: storage), summary)
    }

    func testReturnInAnItemStartsANewItem() {
        caret(after: "Ship on Thursday.")
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        type("Tell support.")

        XCTAssertEqual(reports.last?.markdown, """
        ## Overview
        The team reviewed the release.
        ## Decisions
        - Ship on Thursday.
        - Tell support.
        - Keep the old onboarding.
        """)
    }

    func testReturnInAnEmptyItemEndsTheList() {
        caret(after: "Keep the old onboarding.")
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        type("Thanks, all.")

        XCTAssertEqual(reports.last?.markdown.components(separatedBy: "\n").last, "Thanks, all.")
    }

    func testReturnAfterAHeadingStartsAParagraph() {
        caret(after: "Decisions")
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        type("Two decisions.")

        XCTAssertTrue(reports.last?.markdown.contains("## Decisions\nTwo decisions.\n- Ship on Thursday.") == true)
    }

    func testAnEmptiedItemLeavesTheSummary() {
        let range = (textView.string as NSString).range(of: "Keep the old onboarding.")
        textView.setSelectedRange(range)
        textView.deleteBackward(nil)

        XCTAssertFalse(reports.last?.markdown.contains("- \n") ?? true)
        XCTAssertEqual(reports.last?.markdown.components(separatedBy: "\n").last, "- Ship on Thursday.")
    }

    func testAClickInAndOutIsNoEdit() {
        caret(after: "Overview")

        window.makeFirstResponder(nil)

        XCTAssertTrue(reports.isEmpty)
    }

    func testUndoReportsTheOldSummary() throws {
        caret(after: "release")
        type(" plan")
        textView.breakUndoCoalescing()

        try XCTUnwrap(textView.undoManager).undo()

        XCTAssertEqual(reports.last?.markdown, summary)
    }

    func testTheEndOfAnEditReportsAnEditOnce() {
        caret(after: "release")
        type(" plan")

        window.makeFirstResponder(nil)

        XCTAssertEqual(reports.map(\.ended), [false, true])
        XCTAssertEqual(reports.last?.markdown.contains("the release plan."), true)
    }
}
