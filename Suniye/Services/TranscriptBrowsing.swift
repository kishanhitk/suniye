import Foundation

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
        searchText: String
    ) -> [RecentResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return results
        }
        return results.filter { $0.text.localizedCaseInsensitiveContains(query) }
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
