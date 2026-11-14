import XCTest
@testable import Suniye

final class MeetingListTextTests: XCTestCase {
    private let text = MeetingListText(
        summary: "## Overview\nThe team will ship on Thursday. Legal reviews the copy.\n\n## Action items\n- Ask legal about the pricing page.",
        notes: "Pricing page\n- Keep the old copy",
        transcript: ["Thanks for joining.", "QA found one crash with Bluetooth headsets."]
    )

    func testTheSnippetFollowsTheMeetingState() {
        XCTAssertEqual(text.snippet(for: .done), "The team will ship on Thursday.")
        XCTAssertEqual(text.snippet(for: .summaryFailed), "Couldn’t write the summary.")
        XCTAssertEqual(text.snippet(for: .noSpeech), "Too little speech to summarize.")
        XCTAssertEqual(text.snippet(for: .interrupted), "Thanks for joining.")
    }

    func testASearchFindsTheLineInTheSummaryNotesOrTranscript() {
        XCTAssertEqual(text.line(matching: "legal about"), "Ask legal about the pricing page.")
        XCTAssertEqual(text.line(matching: "old copy"), "- Keep the old copy")
        XCTAssertEqual(text.line(matching: "bluetooth"), "QA found one crash with Bluetooth headsets.")
        XCTAssertNil(text.line(matching: "Overview"), "headings are not content")
    }

    func testDurationsReadAsMinutesAndHours() {
        XCTAssertEqual(MeetingDurationText.text(20), "1 min")
        XCTAssertEqual(MeetingDurationText.text(38 * 60), "38 min")
        XCTAssertEqual(MeetingDurationText.text(112 * 60), "1 h 52 min")
        XCTAssertEqual(MeetingDurationText.text(7_200), "2 h")
        XCTAssertEqual(MeetingDurationText.spelledOut(4 * 60 * 60), "4 hours")
        XCTAssertEqual(MeetingDurationText.spelledOut(15 * 60), "15 minutes")
    }
}

final class MeetingExportTests: XCTestCase {
    func testMarkdownHoldsTheSummaryNotesAndTimedTranscript() {
        let record = MeetingRecord(title: "Release plan", startedAt: Date(), tracks: [.you, .them], templateID: "general", pauses: [MeetingPause(start: 30, end: 90)])
        let segments = [
            MeetingSegment(id: UUID(), track: .them, audioStart: 0, audioEnd: 32_000, text: "Ship Thursday?"),
            MeetingSegment(id: UUID(), track: .you, audioStart: 640_000, audioEnd: 672_000, text: "Yes."),
        ]

        let markdown = MeetingExport.markdown(record: record, summary: "## Overview\nShip Thursday.", notes: "Ask legal.\n", segments: segments)

        XCTAssertEqual(markdown, """
        # Release plan

        ## Overview
        Ship Thursday.

        ## Notes
        Ask legal.

        ## Transcript
        [00:00] Them: Ship Thursday?
        [01:40] You: Yes.

        """)
    }

    func testSummaryBlocksAreHeadingsItemsAndParagraphs() {
        XCTAssertEqual(
            MeetingSummaryBlock.parse("## Overview\nShip it.\n\n- Ask legal."),
            [.heading("Overview"), .paragraph("Ship it."), .item("Ask legal.")]
        )
    }
}

final class MeetingNotesDraftTests: XCTestCase {
    func testOnlyAnEditIsSavedAndEachEditOnce() {
        var draft = MeetingNotesDraft(saved: "Ask legal.")

        let unchanged = draft.takeUnsaved()
        draft.text = "Ask legal.\nShip Thursday."
        let edited = draft.takeUnsaved()
        let again = draft.takeUnsaved()
        draft.text = "Ask legal."
        let undone = draft.takeUnsaved()

        XCTAssertNil(unchanged, "notes that only loaded are never written over")
        XCTAssertEqual(edited, "Ask legal.\nShip Thursday.")
        XCTAssertNil(again)
        XCTAssertEqual(undone, "Ask legal.", "the loaded text saves again after an edit was saved")
    }
}
