import XCTest
@testable import Suniye

final class DictationWordCountTests: XCTestCase {
    /// A whitespace split counts a whole CJK sentence as one word. Suniye ships
    /// multilingual recognizers, so that silently zeroed those users' totals.
    func testWordCountSegmentsScriptsWrittenWithoutSpaces() {
        XCTAssertEqual("Send the report by Friday morning please.".dictationWordCount, 7)
        XCTAssertEqual("कल सुबह मीटिंग है".dictationWordCount, 4)
        XCTAssertGreaterThan("明天早上有个会议我需要发送报告".dictationWordCount, 1)
        XCTAssertGreaterThan("明日の朝に会議があるので報告書を送る".dictationWordCount, 1)
    }

    func testWordCountIgnoresPunctuationAndEmptyText() {
        XCTAssertEqual("".dictationWordCount, 0)
        XCTAssertEqual("   \n  ".dictationWordCount, 0)
        XCTAssertEqual("Hello, world!".dictationWordCount, 2)
    }
}

final class DictationStatsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: iso)!
    }

    func testRecordAccumulatesLifetimeAndDayBuckets() {
        var stats = DictationStats.empty
        stats.record(words: 10, seconds: 20, on: date("2026-08-16 09:00"), calendar: calendar)
        stats.record(words: 5, seconds: 10, on: date("2026-08-16 17:30"), calendar: calendar)
        stats.record(words: 7, seconds: 14, on: date("2026-08-15 11:00"), calendar: calendar)

        XCTAssertEqual(stats.lifetimeSessions, 3)
        XCTAssertEqual(stats.lifetimeWords, 22)
        XCTAssertEqual(stats.lifetimeSeconds, 44)
        XCTAssertEqual(stats.days["2026-08-16"], DictationDayStats(sessions: 2, words: 15, seconds: 30))
        XCTAssertEqual(stats.days["2026-08-15"], DictationDayStats(sessions: 1, words: 7, seconds: 14))
    }

    /// Late-night dictation belongs to the day the user was awake for, which is
    /// the local civil date — not UTC.
    func testDayKeyUsesLocalCivilDate() {
        // 23:45 in Kolkata is already the next day in UTC.
        XCTAssertEqual(DictationStats.dayKey(for: date("2026-08-16 23:45"), calendar: calendar), "2026-08-16")
        XCTAssertEqual(DictationStats.dayKey(for: date("2026-08-17 00:15"), calendar: calendar), "2026-08-17")
    }

    func testAverageWordsPerMinuteAndEmptyGuards() {
        var stats = DictationStats.empty
        XCTAssertEqual(stats.averageWordsPerMinute, 0)

        stats.record(words: 120, seconds: 60, on: date("2026-08-16 09:00"), calendar: calendar)
        XCTAssertEqual(stats.averageWordsPerMinute, 120)
    }

    func testTimeSavedIsFlooredAtZero() {
        var stats = DictationStats.empty
        // Two words in a minute is slower than typing; a negative saving is not
        // a number worth showing.
        stats.record(words: 2, seconds: 60, on: date("2026-08-16 09:00"), calendar: calendar)
        XCTAssertEqual(stats.timeSavedSeconds(), 0)

        var fast = DictationStats.empty
        // 400 words in 60s; typing at 40 wpm would take 600s.
        fast.record(words: 400, seconds: 60, on: date("2026-08-16 09:00"), calendar: calendar)
        XCTAssertEqual(fast.timeSavedSeconds(), 540, accuracy: 0.001)
    }

    func testStreakCountsConsecutiveDays() {
        var stats = DictationStats.empty
        for day in ["2026-08-14", "2026-08-15", "2026-08-16"] {
            stats.record(words: 5, seconds: 5, on: date("\(day) 10:00"), calendar: calendar)
        }
        XCTAssertEqual(stats.currentStreakDays(endingOn: date("2026-08-16 18:00"), calendar: calendar), 3)
    }

    /// A day with no dictation *yet* is still in progress — the streak must not
    /// reset every morning.
    func testStreakSurvivesADayThatHasNotStartedYet() {
        var stats = DictationStats.empty
        stats.record(words: 5, seconds: 5, on: date("2026-08-14 10:00"), calendar: calendar)
        stats.record(words: 5, seconds: 5, on: date("2026-08-15 10:00"), calendar: calendar)

        XCTAssertEqual(stats.currentStreakDays(endingOn: date("2026-08-16 07:00"), calendar: calendar), 2)
    }

    func testStreakIsZeroAfterAMissedDay() {
        var stats = DictationStats.empty
        stats.record(words: 5, seconds: 5, on: date("2026-08-10 10:00"), calendar: calendar)

        XCTAssertEqual(stats.currentStreakDays(endingOn: date("2026-08-16 07:00"), calendar: calendar), 0)
    }

    func testRecentDayKeysAreContiguousAndOldestFirst() {
        let keys = DictationStats.recentDayKeys(count: 3, endingOn: date("2026-08-16 09:00"), calendar: calendar)
        XCTAssertEqual(keys, ["2026-08-14", "2026-08-15", "2026-08-16"])
    }

    /// Buckets are bounded, lifetime totals are not — trimming must never shrink
    /// the number the user is proud of.
    func testTrimmingOldDaysKeepsLifetimeTotals() {
        var stats = DictationStats.empty
        let today = date("2026-08-16 09:00")
        for offset in 0..<(DictationStats.retainedDays + 30) {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            stats.record(words: 2, seconds: 1, on: day, calendar: calendar, now: today)
        }

        XCTAssertEqual(stats.lifetimeSessions, DictationStats.retainedDays + 30)
        XCTAssertEqual(stats.lifetimeWords, (DictationStats.retainedDays + 30) * 2)
        XCTAssertLessThanOrEqual(stats.days.count, DictationStats.retainedDays)
    }
}

final class DictationStatsStorePersistenceTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-stats-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("stats.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func waitForWrite() {
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: fileURL.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func testRecordedStatsSurviveReload() {
        let store = DictationStatsStore(fileURL: fileURL)
        store.record(words: 12, seconds: 30, at: Date())
        waitForWrite()

        let reloaded = DictationStatsStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.stats.lifetimeSessions, 1)
        XCTAssertEqual(reloaded.stats.lifetimeWords, 12)
        XCTAssertEqual(reloaded.stats.lifetimeSeconds, 30)
    }

    func testSeedingRunsOnceAcrossLaunches() {
        let history = [
            RecentResult(id: UUID(), text: "hello world", createdAt: .now, durationSeconds: 2, wasLLMPolished: false),
            RecentResult(id: UUID(), text: "three word phrase", createdAt: .now, durationSeconds: 3, wasLLMPolished: false)
        ]

        let store = DictationStatsStore(fileURL: fileURL)
        store.seedFromHistoryIfNeeded(history)
        waitForWrite()
        XCTAssertEqual(store.stats.lifetimeWords, 5)

        // A second launch must not fold the same history in again.
        let relaunched = DictationStatsStore(fileURL: fileURL)
        relaunched.seedFromHistoryIfNeeded(history)
        XCTAssertEqual(relaunched.stats.lifetimeSessions, 2)
        XCTAssertEqual(relaunched.stats.lifetimeWords, 5)
    }

    /// Stats are not worth failing a launch over.
    func testCorruptFileIsTreatedAsEmpty() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ not json".utf8).write(to: fileURL)

        let store = DictationStatsStore(fileURL: fileURL)
        XCTAssertEqual(store.stats, .empty)
    }

    func testMissingFileStartsEmpty() {
        let store = DictationStatsStore(fileURL: fileURL)
        XCTAssertEqual(store.stats.lifetimeSessions, 0)
        XCTAssertFalse(store.stats.didSeedFromHistory)
    }
}
