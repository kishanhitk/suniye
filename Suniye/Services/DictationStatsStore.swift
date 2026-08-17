import Foundation

/// One local-calendar day of dictation activity.
struct DictationDayStats: Codable, Equatable {
    var sessions: Int
    var words: Int
    var seconds: TimeInterval

    static let zero = DictationDayStats(sessions: 0, words: 0, seconds: 0)
}

/// What the dashboard reports.
///
/// Lifetime counters are monotonic and independent of the history list, so
/// deleting a transcript no longer rewrites the user's past — that was the whole
/// point of this type. Day buckets exist for the activity chart and the streak
/// and are trimmed to a bounded window; lifetime totals are never trimmed.
struct DictationStats: Codable, Equatable {
    /// Bumped only when the on-disk shape changes incompatibly.
    static let currentVersion = 1
    /// Roughly a year of buckets — enough for the chart, the streak, and a
    /// future year view, while keeping the file trivially small.
    static let retainedDays = 400

    var version = DictationStats.currentVersion
    var lifetimeSessions = 0
    var lifetimeWords = 0
    var lifetimeSeconds: TimeInterval = 0
    /// Keyed by `DictationStats.dayKey(for:)` — a local-calendar `yyyy-MM-dd`.
    var days: [String: DictationDayStats] = [:]
    /// Set once existing history has been folded in, so the migration cannot
    /// double-count on a later launch.
    var didSeedFromHistory = false

    static let empty = DictationStats()

    // MARK: - Day keys

    /// Formatter for day keys. POSIX locale so the key never changes shape with
    /// the user's locale; the time zone is deliberately the current one, so a
    /// dictation is filed under the day the user experienced it.
    private static func dayKeyFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        dayKeyFormatter(timeZone: calendar.timeZone).string(from: date)
    }

    /// The `count` day keys ending today, oldest first. Built by calendar-day
    /// arithmetic rather than 86_400-second steps, so DST days do not skew it.
    static func recentDayKeys(count: Int, endingOn date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> [String] {
        guard count > 0 else {
            return []
        }
        let formatter = dayKeyFormatter(timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map(formatter.string(from:))
        }
    }

    // MARK: - Derived values

    var averageWordsPerMinute: Int {
        guard lifetimeSeconds >= 1, lifetimeWords > 0 else {
            return 0
        }
        return Int((Double(lifetimeWords) / (lifetimeSeconds / 60)).rounded())
    }

    /// Seconds saved against typing the same words by hand. Floored at zero: a
    /// negative "saving" is not a thing worth reporting to the user.
    func timeSavedSeconds(typingWordsPerMinute: Double = DictationStats.assumedTypingWordsPerMinute) -> TimeInterval {
        guard typingWordsPerMinute > 0 else {
            return 0
        }
        let typingSeconds = Double(lifetimeWords) / typingWordsPerMinute * 60
        return max(0, typingSeconds - lifetimeSeconds)
    }

    /// Average sustained typing speed for an adult on a physical keyboard. Shown
    /// to the user next to the number rather than hidden, because the whole
    /// metric rests on it.
    static let assumedTypingWordsPerMinute: Double = 40

    /// Consecutive days with at least one dictation, ending today. A day with no
    /// dictation *yet* does not break the streak — it is still in progress — so
    /// the walk starts at yesterday when today is empty.
    func currentStreakDays(endingOn date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Int {
        let formatter = Self.dayKeyFormatter(timeZone: calendar.timeZone)
        var day = calendar.startOfDay(for: date)

        if (days[formatter.string(from: day)]?.sessions ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else {
                return 0
            }
            day = yesterday
        }

        var streak = 0
        while (days[formatter.string(from: day)]?.sessions ?? 0) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previous
        }
        return streak
    }

    func words(forDayKeys keys: [String]) -> [Int] {
        keys.map { days[$0]?.words ?? 0 }
    }

    // MARK: - Mutation

    /// `now` anchors retention. It is deliberately separate from `date`: seeding
    /// replays historical dictations, and trimming against the entry being
    /// written would keep everything newer than the oldest one — i.e. trim nothing.
    mutating func record(
        words: Int,
        seconds: TimeInterval,
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) {
        lifetimeSessions += 1
        lifetimeWords += words
        lifetimeSeconds += seconds

        let key = Self.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? .zero
        day.sessions += 1
        day.words += words
        day.seconds += seconds
        days[key] = day

        trimDays(endingOn: now, calendar: calendar)
    }

    private mutating func trimDays(endingOn date: Date, calendar: Calendar) {
        guard days.count > Self.retainedDays else {
            return
        }
        let retained = Set(Self.recentDayKeys(count: Self.retainedDays, endingOn: date, calendar: calendar))
        // Keys ahead of today (a clock that was set backwards) are kept: they are
        // real recorded activity, and dropping them would lose words for good.
        let today = Self.dayKey(for: date, calendar: calendar)
        days = days.filter { retained.contains($0.key) || $0.key > today }
    }
}

/// One bar of the activity chart.
struct DailyWordCount: Identifiable, Equatable {
    let dayKey: String
    let words: Int

    var id: String { dayKey }

    /// Midnight of this bucket's day, for chart axis labelling.
    var date: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = Calendar.autoupdatingCurrent.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayKey)
    }
}

protocol DictationStatsStoring: AnyObject {
    var stats: DictationStats { get }
    func record(words: Int, seconds: TimeInterval, at date: Date)
    func seedFromHistoryIfNeeded(_ results: [RecentResult])
}

/// Durable, bounded, and cheap to update: the in-memory snapshot is authoritative
/// for the UI and the write is pushed off the calling (main) actor, because every
/// `record` happens on the latency-sensitive dictation-completion path.
final class DictationStatsStore: DictationStatsStoring {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.suniye.stats", qos: .utility)
    private let calendar: Calendar
    private var snapshot: DictationStats

    var stats: DictationStats {
        snapshot
    }

    init(fileURL: URL = DictationStatsStore.defaultFileURL(), calendar: Calendar = .autoupdatingCurrent) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.snapshot = Self.read(from: fileURL)
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Suniye", isDirectory: true)
            .appendingPathComponent("stats.json")
    }

    func record(words: Int, seconds: TimeInterval, at date: Date = Date()) {
        snapshot.record(words: words, seconds: seconds, on: date, calendar: calendar)
        persist()
    }

    /// Folds pre-existing history into the counters exactly once, so upgrading
    /// does not reset anybody's numbers to zero.
    func seedFromHistoryIfNeeded(_ results: [RecentResult]) {
        guard !snapshot.didSeedFromHistory else {
            return
        }
        for result in results.sorted(by: { $0.createdAt < $1.createdAt }) {
            snapshot.record(
                words: result.wordCount,
                seconds: result.durationSeconds,
                on: result.createdAt,
                calendar: calendar
            )
        }
        snapshot.didSeedFromHistory = true
        persist()
    }

    private func persist() {
        let value = snapshot
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(value) else {
                return
            }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic: a crash mid-write loses the last dictation, never the file.
            try? data.write(to: url, options: .atomic)
        }
    }

    /// A corrupt or future-version file is treated as absent rather than fatal —
    /// stats are not worth failing a launch over. Seeding then rebuilds what
    /// history still holds.
    private static func read(from url: URL) -> DictationStats {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(DictationStats.self, from: data),
            decoded.version <= DictationStats.currentVersion
        else {
            return .empty
        }
        return decoded
    }
}
