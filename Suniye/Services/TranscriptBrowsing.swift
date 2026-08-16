import Foundation

/// Time window shown on the Transcripts page.
enum TranscriptFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case today
    case lastSevenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .today:
            return "Today"
        case .lastSevenDays:
            return "Last 7 days"
        }
    }

    func includes(_ date: Date, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .lastSevenDays:
            // Seven calendar days including today, not a rolling 168 hours — a
            // dictation from 8 days ago at 23:00 should not still be "last 7 days".
            guard let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else {
                return true
            }
            return date >= cutoff
        }
    }
}

/// One day's transcripts, newest first.
struct TranscriptDayGroup: Identifiable, Equatable {
    let id: String
    let date: Date
    let results: [RecentResult]
}

enum TranscriptBrowser {
    /// Filter by window, then by free text, preserving the newest-first order the
    /// history already has. Search matches transcript text only — the meta line
    /// (time, app, duration) is chrome, not content the user is looking for.
    static func filter(
        _ results: [RecentResult],
        filter: TranscriptFilter,
        searchText: String,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [RecentResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return results.filter { result in
            guard filter.includes(result.createdAt, now: now, calendar: calendar) else {
                return false
            }
            guard !query.isEmpty else {
                return true
            }
            return result.text.localizedCaseInsensitiveContains(query)
        }
    }

    /// Groups into calendar days, newest day first. Input is assumed newest-first
    /// (history is stored that way), so groups keep that order without re-sorting.
    static func group(
        _ results: [RecentResult],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [TranscriptDayGroup] {
        var groups: [TranscriptDayGroup] = []
        var currentKey: String?
        var current: [RecentResult] = []
        var currentDate = Date()

        func flush() {
            guard let key = currentKey, !current.isEmpty else {
                return
            }
            groups.append(TranscriptDayGroup(id: key, date: currentDate, results: current))
        }

        for result in results {
            let key = DictationStats.dayKey(for: result.createdAt, calendar: calendar)
            if key != currentKey {
                flush()
                currentKey = key
                currentDate = calendar.startOfDay(for: result.createdAt)
                current = []
            }
            current.append(result)
        }
        flush()

        return groups
    }

    /// "Today" / "Yesterday" / "12 August" — a date the user has to decode is a
    /// worse header than a word they read at a glance.
    static func dayTitle(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let sameYear = calendar.dateComponents([.year], from: date).year,
           sameYear == calendar.dateComponents([.year], from: now).year {
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }
}
