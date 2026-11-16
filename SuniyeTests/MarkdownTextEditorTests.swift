import AppKit
import SwiftUI
import XCTest
@testable import Suniye

/// Drives the Markdown editor through its real text view, in a window that
/// never shows.
@MainActor
final class MarkdownTextEditorTests: XCTestCase {
    private let summary = """
    ## Overview
    The team will ship on **Thursday**.
    ## Decisions
    - Ship on Thursday.
    - Keep the old onboarding.
    """
    /// Taller once styled than in the first layout: the last line once drew
    /// outside the area that AppKit draws.
    private let mixedScripts = """
    ## Overview
    The team agreed to move the invoice export to https://example.com/billing/exports/2026/november/very-long-path-that-does-not-break?ref=meeting-summary before the audit. 🎉
    ## निर्णय
    - टीम गुरुवार को रिलीज़ भेजेगी, और **सहायता टीम** को नए बटन के बारे में बताएगी।
    - Keep the old onboarding for one more release 👍 and **ask legal** about the copy in Germany, France and Japan.
    ## Steps
    1. Merge the fix for the 日本語 input bug.
    2. Send QA the build. Supercalifragilisticexpialidociouslylongwordwithoutanyspacesatall
    """
    private var window: NSWindow!
    private var host: MarkdownTextEditor.Host!
    private var reports: [(markdown: String, ended: Bool)] = []

    private func open(_ markdown: String, size: CGSize = CGSize(width: 600, height: 400)) async throws -> NSTextView {
        let model = MarkdownTextEditor.Model(markdown: markdown, documentID: UUID().uuidString)
        model.isEditable = true
        model.edited = { [weak self] markdown, ended in self?.reports.append((markdown, ended)) }
        host = MarkdownTextEditor.Host(model: model)
        host.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await settle()
        return try XCTUnwrap(host.editorTextView)
    }

    /// The engine sends its text to the binding on the next turn of the main queue.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    override func tearDown() async throws {
        window?.close()
    }

    func testASummaryThatAModelWroteOpensWithNoChange() async throws {
        for markdown in RealMeetingSummaries.all {
            reports = []
            let text = try await open(markdown)
            XCTAssertTrue(window.makeFirstResponder(text))
            window.makeFirstResponder(nil)
            try await settle()

            XCTAssertEqual(text.string, markdown)
            XCTAssertTrue(reports.isEmpty, "a click in and out is no edit")
            window.close()
        }
    }

    func testReturnInAnItemStartsANewItem() async throws {
        let text = try await open(summary)
        XCTAssertTrue(window.makeFirstResponder(text))
        let item = (text.string as NSString).range(of: "Ship on Thursday.")
        text.setSelectedRange(NSRange(location: NSMaxRange(item), length: 0))

        text.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        text.insertText("Tell support.", replacementRange: text.selectedRange())
        try await settle()

        XCTAssertEqual(reports.last?.markdown.contains("- Ship on Thursday.\n- Tell support.\n- Keep the old onboarding."), true)
        XCTAssertEqual(reports.last?.ended, false)
    }

    func testReturnInAnEmptyItemEndsTheList() async throws {
        let text = try await open(summary)
        XCTAssertTrue(window.makeFirstResponder(text))
        let item = (text.string as NSString).range(of: "Keep the old onboarding.")
        text.setSelectedRange(NSRange(location: NSMaxRange(item), length: 0))

        text.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        text.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        text.insertText("After the list.", replacementRange: text.selectedRange())
        try await settle()

        XCTAssertEqual(reports.last?.markdown.hasSuffix("- Keep the old onboarding.\nAfter the list."), true, reports.last?.markdown ?? "")
    }

    func testAnEditEndsWhenTheEditorLeavesItsWindow() async throws {
        let text = try await open(summary)
        XCTAssertTrue(window.makeFirstResponder(text))
        text.setSelectedRange(NSRange(location: (summary as NSString).length, length: 0))
        text.insertText(" Today.", replacementRange: text.selectedRange())
        try await settle()

        window.contentView = nil
        try await settle()

        XCTAssertEqual(reports.last?.ended, true)
        XCTAssertEqual(reports.last?.markdown.hasSuffix("Keep the old onboarding. Today."), true)
    }

    func testAnUndoReachesTheSave() async throws {
        let text = try await open(summary)
        XCTAssertTrue(window.makeFirstResponder(text))
        text.setSelectedRange(NSRange(location: (text.string as NSString).range(of: "Thursday**.").location, length: 0))
        text.insertText("next ", replacementRange: text.selectedRange())
        text.breakUndoCoalescing()

        try XCTUnwrap(text.undoManager).undo()
        try await settle()

        XCTAssertEqual(reports.last?.markdown, summary, "the save writes the text from before the typing")
    }

    func testTheEndOfAnEditReportsItOnceAndOnlyAfterAChange() async throws {
        let text = try await open(summary)
        XCTAssertTrue(window.makeFirstResponder(text))
        text.setSelectedRange(NSRange(location: (summary as NSString).length, length: 0))
        text.insertText(" Today.", replacementRange: text.selectedRange())
        try await settle()

        window.makeFirstResponder(nil)
        try await settle()
        XCTAssertTrue(window.makeFirstResponder(text))
        window.makeFirstResponder(nil)
        try await settle()

        XCTAssertEqual(reports.map(\.ended), [false, true])
        XCTAssertEqual(reports.last?.markdown.hasSuffix("Keep the old onboarding. Today."), true)
    }

    func testAPageTextDuringAnEditIsNoEditWhenTheEditEnds() async throws {
        let text = try await open(summary)
        XCTAssertTrue(window.makeFirstResponder(text))
        text.setSelectedRange(NSRange(location: (summary as NSString).length, length: 0))
        text.insertText(" Today.", replacementRange: text.selectedRange())
        try await settle()

        host.model.load("## Overview\nA new summary.")
        try await settle()
        window.makeFirstResponder(nil)
        try await settle()

        XCTAssertEqual(reports.map(\.ended), [false])
    }

    func testAPageTextThatChangesShowsAndIsNoEdit() async throws {
        let text = try await open(summary)

        host.model.load("## Overview\nA new summary.")
        try await settle()

        XCTAssertEqual(text.string, "## Overview\nA new summary.")
        XCTAssertTrue(reports.isEmpty)
    }

    func testTheLastLineOfAShortSummaryDraws() async throws {
        let text = try await open(mixedScripts, size: CGSize(width: 520, height: 500))
        let layout = try XCTUnwrap(text.textLayoutManager)
        var last = CGRect.null
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            last = fragment.layoutFragmentFrame
            return true
        }
        XCTAssertLessThan(last.maxY, text.bounds.height, "the summary is shorter than the view")
        let line = last.offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
        let image = try XCTUnwrap(text.bitmapImageRepForCachingDisplay(in: line))
        text.cacheDisplay(in: line, to: image)

        XCTAssertGreaterThan(Self.inkedPixels(in: image), 100, "the last line shows")
    }

    private static func inkedPixels(in image: NSBitmapImageRep) -> Int {
        var count = 0
        for x in 0..<image.pixelsWide {
            for y in 0..<image.pixelsHigh where (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                count += 1
            }
        }
        return count
    }

    func testAClosedEditorReleasesItsTextView() async throws {
        weak var closed = try await open(summary)
        window.contentView = nil
        window.close()
        window = nil
        host = nil

        // AppKit releases a text view after its delayed spell-check work runs.
        let deadline = Date().addingTimeInterval(5)
        while closed != nil, Date() < deadline {
            try await settle()
        }
        XCTAssertNil(closed)
    }

    func testCommandFOpensTheFindBarOverTheText() async throws {
        let text = try await open(summary)
        XCTAssertTrue(window.makeFirstResponder(text))
        let show = NSMenuItem()
        show.tag = NSTextFinder.Action.showFindInterface.rawValue

        text.performTextFinderAction(show)

        XCTAssertEqual(text.enclosingScrollView?.isFindBarVisible, true)
    }
}
