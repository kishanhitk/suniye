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

    func testTheSnippetSkipsHeadingsOfEveryLevel() {
        let text = MeetingListText(summary: "# Release 2.4\n### Overview\n#hashtag stays. It is no heading.", notes: "", transcript: [])

        XCTAssertEqual(text.snippet(for: .done), "#hashtag stays.")
    }

    func testASummaryShowsWithoutMarkdownMarks() {
        let text = MeetingListText(
            summary: "## Decisions\n1. **Decision:** ship on *Friday*. QA signs off.\n2. Read [the spec](https://example.com/spec) and run `make test`.\n- [ ] Ask legal\n- [x] Tell support",
            notes: "",
            transcript: []
        )

        XCTAssertEqual(text.snippet(for: .done), "Decision: ship on Friday.")
        XCTAssertEqual(text.line(matching: "spec"), "Read the spec and run make test.")
        XCTAssertEqual(text.line(matching: "legal"), "Ask legal")
        XCTAssertEqual(text.line(matching: "support"), "Tell support")
        XCTAssertNil(text.line(matching: "example.com"), "a link shows only its text")
    }

    func testEachBlockOfASummaryIsOneLine() {
        let summary = """
        Para one.
        ## Mid
        Para two
        on two lines.
        - outer
          - [ ] inner task

          [x] stays: a task mark starts only the first paragraph.
        - `[x] stays in code`
        - # Section

          [x] stays after a heading
        - ```
          [x] stays in a code block
          ```
        > quoted **line**

        | A | B |
        |---|---|
        | 1 | 2 |

        ```
        code one
        code two
        ```
        """

        XCTAssertEqual(MeetingListText(summary: summary, notes: "", transcript: []).summaryLines, [
            "Para one.", "Para two", "on two lines.", "outer", "inner task",
            "[x] stays: a task mark starts only the first paragraph.", "[x] stays in code",
            "[x] stays after a heading", "[x] stays in a code block",
            "quoted line", "A", "B", "1", "2", "code one", "code two",
        ])
    }

    func testASearchReadsTheNotesAsPlainTextWithTheirHeadings() {
        let text = MeetingListText(summary: nil, notes: "## Pricing\n1. **Keep** the old copy\n- [ ] Ask [legal](https://example.com/legal)", transcript: [])

        XCTAssertEqual(text.line(matching: "pricing"), "Pricing")
        XCTAssertEqual(text.line(matching: "old copy"), "Keep the old copy")
        XCTAssertEqual(text.line(matching: "legal"), "Ask legal")
    }

    func testASearchFindsTheLineInTheSummaryNotesOrTranscript() {
        XCTAssertEqual(text.line(matching: "legal about"), "Ask legal about the pricing page.")
        XCTAssertEqual(text.line(matching: "old copy"), "Keep the old copy")
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
}
