import Foundation
import Observation

/// The transcript history and the dictation totals. Each change saves at once.
@MainActor
@Observable
final class DictationLibrary {
    /// Newest first.
    private(set) var results: [RecentResult]
    /// Mirrored from the stats store, so that no view body sums day buckets.
    private(set) var stats: DictationStats
    /// Where dictation lands most. Rebuilt when the history changes, not per read.
    private(set) var topApps: [DictationAppUsage] = []

    @ObservationIgnored private let historyStore: HistoryStoreProtocol
    @ObservationIgnored private let statsStore: DictationStatsStoring

    init(historyStore: HistoryStoreProtocol, statsStore: DictationStatsStoring) {
        self.historyStore = historyStore
        self.statsStore = statsStore
        let results = historyStore.load()
        // Folds history from before the counters existed into them once, so an
        // upgrade does not reset anyone's numbers. Old history cannot tell Edit
        // Mode rewrites apart, so the seeded totals include them.
        statsStore.seedFromHistoryIfNeeded(results)
        self.results = results
        stats = statsStore.stats
        topApps = Self.topApps(in: results)
    }

    var lastTranscriptText: String? {
        results.first?.text
    }

    func insert(_ result: RecentResult) {
        results.insert(result, at: 0)
        historyDidChange()
    }

    /// Records the app a stored transcript landed in, once the insertion succeeded.
    func attribute(_ id: UUID, to bundleID: String?) {
        guard let bundleID, let index = results.firstIndex(where: { $0.id == id }) else {
            return
        }
        results[index].appBundleID = bundleID
        historyDidChange()
    }

    func delete(_ result: RecentResult) {
        results.removeAll { $0.id == result.id }
        historyDidChange()
    }

    func replaceResults(_ newResults: [RecentResult]) {
        results = newResults
        historyDidChange()
    }

    func recordDictation(words: Int, seconds: TimeInterval, at date: Date) {
        statsStore.record(words: words, seconds: seconds, at: date)
        stats = statsStore.stats
    }

    /// Called on termination: see `DictationStatsStore.flush()`.
    func flush() {
        statsStore.flush()
    }

    private func historyDidChange() {
        historyStore.save(results)
        topApps = Self.topApps(in: results)
    }

    /// Counts are a floor, not a share: the source app was only recorded from a
    /// certain version on, and older transcripts carry no bundle ID at all.
    private static func topApps(in results: [RecentResult]) -> [DictationAppUsage] {
        var counts: [String: Int] = [:]
        for result in results {
            guard let bundleID = result.appBundleID else {
                continue
            }
            counts[bundleID, default: 0] += 1
        }

        return counts
            // Drop apps that are no longer installed before cutting to three,
            // otherwise an uninstalled leader takes an installed fourth place
            // down with it and the header shows fewer apps than it has.
            .compactMap { bundleID, count -> DictationAppUsage? in
                guard let name = DictationAppUsage.resolvedName(for: bundleID) else {
                    return nil
                }
                return DictationAppUsage(bundleID: bundleID, count: count, name: name)
            }
            // Equal counts sort by bundle ID, so that they do not reshuffle on every rebuild.
            .sorted { ($0.count, $1.bundleID) > ($1.count, $0.bundleID) }
            .prefix(3)
            .map { $0 }
    }
}
