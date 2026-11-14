import AppKit
import XCTest
@testable import Suniye

/// Drives the title through its real text view, in a window that never
/// shows.
@MainActor
final class MeetingTitleFieldTests: XCTestCase {
    private var window: NSWindow!
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var coordinator: MeetingTitleField.Coordinator!
    private var renamed: [String] = []

    override func setUp() async throws {
        coordinator = MeetingTitleField.Coordinator(title: "Q3 launch review") { [weak self] in self?.renamed.append($0) }
        scrollView = MeetingTitleField.makeView(title: "Q3 launch review", delegate: coordinator)
        textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        scrollView.frame = CGRect(x: 10, y: 20, width: 400, height: MeetingTitleField.height)
        window.contentView?.addSubview(scrollView)
    }

    override func tearDown() async throws {
        window.close()
    }

    /// Begins an edit and replaces the title with `text`, as typing does.
    private func type(_ text: String) {
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.selectAll(nil)
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    func testReturnKeepsTheTypedTitleAndEndsTheEdit() {
        type("Q4 planning ")

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(renamed, ["Q4 planning"])
        XCTAssertFalse(window.firstResponder === textView)
        XCTAssertEqual(textView.string, "Q4 planning ")
    }

    func testEscDropsTheTypedTitle() {
        type("Q4 planning")

        textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertEqual(renamed, [])
        XCTAssertEqual(textView.string, "Q3 launch review")
        XCTAssertFalse(window.firstResponder === textView)
    }

    func testAClickElsewhereKeepsTheTypedTitle() {
        type("Q4 planning")

        window.makeFirstResponder(nil)

        XCTAssertEqual(renamed, ["Q4 planning"])
    }

    func testAnEmptyTitleGoesBackToTheOldOne() {
        type("   ")

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(renamed, [])
        XCTAssertEqual(textView.string, "Q3 launch review")
    }

    func testAnEditThatChangesNothingDoesNotRename() {
        type("Q3 launch review")

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(renamed, [])
    }

    func testAPastedTitleWithLineBreaksStaysOneLine() {
        type("Q4\nplanning")

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(renamed, ["Q4 planning"])
    }

    func testLeavingThePageDuringAnEditKeepsTheTypedTitle() {
        type("Q4 planning")

        scrollView.removeFromSuperview()

        XCTAssertEqual(renamed, ["Q4 planning"])
    }
}
