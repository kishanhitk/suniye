import XCTest
@testable import Suniye

final class TranscriptBrowsingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func result(_ text: String, _ dateValue: String, app: String? = nil) -> RecentResult {
        RecentResult(
            id: UUID(),
            text: text,
            createdAt: date(dateValue),
            durationSeconds: 2,
            wasLLMPolished: false,
            appBundleID: app
        )
    }

    // MARK: - Search

    func testSearchIsCaseAndDiacriticFriendlyAndTrimsWhitespace() {
        let results = [
            result("Send the report by Friday", "2026-08-16 09:00"),
            result("unrelated", "2026-08-16 08:00")
        ]

        XCTAssertEqual(TranscriptBrowser.filter(results, searchText: "  FRIDAY ").count, 1)
        XCTAssertEqual(TranscriptBrowser.filter(results, searchText: "").count, 2)
    }

    func testSearchMatchesTranscriptTextOnly() {
        let results = [
            result("report today", "2026-08-16 09:00"),
            result("unrelated", "2026-08-01 09:00", app: "com.example.report")
        ]

        XCTAssertEqual(
            TranscriptBrowser.filter(results, searchText: "report").map(\.text),
            ["report today"]
        )
    }

    // MARK: - Grouping

    func testGroupingSplitsByCalendarDayAndKeepsOrder() {
        let results = [
            result("newest", "2026-08-16 18:00"),
            result("same day", "2026-08-16 09:00"),
            result("older day", "2026-08-14 09:00")
        ]

        let groups = TranscriptBrowser.group(results, calendar: calendar)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].results.map(\.text), ["newest", "same day"])
        XCTAssertEqual(groups[1].results.map(\.text), ["older day"])
    }

    func testGroupingEmptyInputProducesNoGroups() {
        XCTAssertTrue(TranscriptBrowser.group([], calendar: calendar).isEmpty)
    }

    /// A late-night dictation belongs to the day the user experienced, so
    /// grouping must use the local civil date rather than UTC.
    func testGroupingUsesLocalDayBoundaries() {
        let results = [
            result("just before midnight", "2026-08-16 23:50"),
            result("just after midnight", "2026-08-17 00:10")
        ]

        let groups = TranscriptBrowser.group(results, calendar: calendar)

        XCTAssertEqual(groups.count, 2)
    }

    // MARK: - Day titles

    func testDayTitlesPreferWordsOverDates() {
        let now = date("2026-08-16 12:00")

        XCTAssertEqual(TranscriptBrowser.dayTitle(for: date("2026-08-16 09:00"), now: now, calendar: calendar), "Today")
        XCTAssertEqual(TranscriptBrowser.dayTitle(for: date("2026-08-15 09:00"), now: now, calendar: calendar), "Yesterday")

        let older = TranscriptBrowser.dayTitle(for: date("2026-08-10 09:00"), now: now, calendar: calendar)
        XCTAssertNotEqual(older, "Today")
        XCTAssertNotEqual(older, "Yesterday")
        XCTAssertFalse(older.isEmpty)
    }
}

final class RecentResultSourceAppTests: XCTestCase {
    /// History written before the source app was recorded must still decode.
    func testLegacyTranscriptWithoutAppBundleIDDecodes() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","text":"hello","createdAt":1723800000000,"durationSeconds":1.5,"wasLLMPolished":false}]
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode([RecentResult].self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded[0].appBundleID)
        XCTAssertEqual(decoded[0].text, "hello")
    }

    func testMetaLineOmitsUnknownApp() {
        let result = RecentResult(
            id: UUID(),
            text: "two words",
            createdAt: Date(),
            durationSeconds: 3,
            wasLLMPolished: false
        )

        XCTAssertTrue(result.metaLine.contains("2 words"))
        XCTAssertTrue(result.metaLine.contains("3.0s"))
    }
    // MARK: - Highlighting

    private func highlightedRanges(_ text: String, query: String) -> Int {
        let attributed = text.highlightingMatches(of: query)
        return attributed.runs.filter { $0.backgroundColor != nil }.count
    }

    func testHighlightingMarksEveryOccurrence() {
        XCTAssertEqual(highlightedRanges("report the report", query: "report"), 2)
    }

    func testHighlightingIgnoresCaseDiacriticsAndSurroundingWhitespace() {
        XCTAssertEqual(highlightedRanges("Cafe and CAFÉ", query: "  café "), 2)
    }

    func testHighlightingLeavesTextAloneWithoutAQuery() {
        XCTAssertEqual(highlightedRanges("nothing to mark", query: "   "), 0)
        XCTAssertEqual(highlightedRanges("nothing to mark", query: ""), 0)
    }

    func testHighlightingPreservesTheOriginalText() {
        let text = "Ship it Friday"
        XCTAssertEqual(String(text.highlightingMatches(of: "friday").characters), text)
    }

}
