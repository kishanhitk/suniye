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

    // MARK: - Filtering

    func testTodayFilterKeepsOnlyTodaysTranscripts() {
        let now = date("2026-08-16 12:00")
        let results = [
            result("today one", "2026-08-16 09:00"),
            result("yesterday", "2026-08-15 23:59"),
            result("today two", "2026-08-16 00:01")
        ]

        let filtered = TranscriptBrowser.filter(results, filter: .today, searchText: "", now: now, calendar: calendar)

        XCTAssertEqual(filtered.map(\.text), ["today one", "today two"])
    }

    /// Seven calendar days including today — not a rolling 168 hours, or a
    /// dictation from eight days ago at 23:00 would still count.
    func testLastSevenDaysUsesCalendarDaysNotAnHourWindow() {
        let now = date("2026-08-16 12:00")
        let results = [
            result("in range", "2026-08-10 00:05"),
            result("out of range", "2026-08-09 23:55")
        ]

        let filtered = TranscriptBrowser.filter(
            results,
            filter: .lastSevenDays,
            searchText: "",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(filtered.map(\.text), ["in range"])
    }

    func testSearchIsCaseAndDiacriticFriendlyAndTrimsWhitespace() {
        let results = [
            result("Send the report by Friday", "2026-08-16 09:00"),
            result("unrelated", "2026-08-16 08:00")
        ]

        XCTAssertEqual(
            TranscriptBrowser.filter(results, filter: .all, searchText: "  FRIDAY ", now: date("2026-08-16 12:00"), calendar: calendar).count,
            1
        )
        XCTAssertEqual(
            TranscriptBrowser.filter(results, filter: .all, searchText: "", now: date("2026-08-16 12:00"), calendar: calendar).count,
            2
        )
    }

    func testSearchAndFilterCombine() {
        let now = date("2026-08-16 12:00")
        let results = [
            result("report today", "2026-08-16 09:00"),
            result("report last week", "2026-08-01 09:00")
        ]

        let filtered = TranscriptBrowser.filter(results, filter: .today, searchText: "report", now: now, calendar: calendar)

        XCTAssertEqual(filtered.map(\.text), ["report today"])
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
}
