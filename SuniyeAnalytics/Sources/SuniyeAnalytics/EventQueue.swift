import Foundation

/// Durable, append-only offline queue backed by a JSONL file.
///
/// `append` is O(1): it writes a single line to the end of the file and fsyncs,
/// so an event is durable before the call returns (a resident menu-bar app gets
/// no clean shutdown on force-quit/crash) without the caller ever paying an
/// O(n) full-file rewrite. Pruning (TTL + size cap) happens lazily at read time
/// (`peek`), plus an amortized size sweep once the file drifts past the cap by a
/// margin. An in-memory `cachedCount` keeps `count` O(1). Overflow drops the
/// oldest and is surfaced as an eviction count (reported via `analytics_health`).
public final class EventQueue: @unchecked Sendable {
    public struct Config: Sendable {
        public var maxEvents: Int
        public var maxAgeSeconds: TimeInterval
        public init(maxEvents: Int = 5_000, maxAgeSeconds: TimeInterval = 7 * 24 * 60 * 60) {
            self.maxEvents = maxEvents
            self.maxAgeSeconds = maxAgeSeconds
        }
    }

    private let fileURL: URL
    private let config: Config
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Events dropped by TTL/size eviction since the last read of this counter.
    private var evictedCount = 0
    /// In-memory line count so `count` and the flush-threshold check are O(1).
    private var cachedCount = 0

    /// Slack above `maxEvents` before an append triggers an O(n) size sweep, so
    /// the append hot path stays O(1) even at the cap (sweep is amortized).
    private var pruneMargin: Int { max(1, config.maxEvents / 10) }

    public init(fileURL: URL, config: Config = Config()) {
        self.fileURL = fileURL
        self.config = config
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        cachedCount = readAllLocked().count
    }

    /// Persists one event durably (single fsynced line append, O(1)).
    public func append(_ event: EncodedEvent, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard let line = try? encoder.encode(event) else { return }
        appendLineLocked(line)
        cachedCount += 1
        if cachedCount > config.maxEvents + pruneMargin {
            pruneLocked(now: now)
        }
    }

    /// Returns up to `max` oldest events, dropping stale/overflow first.
    public func peek(max: Int, now: Date = Date()) -> [EncodedEvent] {
        lock.lock()
        defer { lock.unlock() }
        let entries = pruneLocked(now: now)
        return entries.prefix(max).compactMap { try? decoder.decode(EncodedEvent.self, from: $0.0) }
    }

    /// Removes the oldest `count` events after a successful send.
    public func removeOldest(_ count: Int) {
        guard count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        var entries = readAllLocked()
        entries.removeFirst(Swift.min(count, entries.count))
        writeAllLocked(entries)
        cachedCount = entries.count
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
        cachedCount = 0
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cachedCount
    }

    /// Returns and resets the eviction counter.
    public func takeEvictedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let value = evictedCount
        evictedCount = 0
        return value
    }

    // MARK: - Locked helpers (caller holds `lock`)

    private func appendLineLocked(_ line: Data) {
        var blob = line
        blob.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: blob)
            try? handle.synchronize() // fsync: durable before returning
        } else {
            // First write — the file doesn't exist yet.
            try? blob.write(to: fileURL, options: [.atomic])
        }
    }

    private func readAllLocked() -> [(Data, Int64)] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        var out: [(Data, Int64)] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            let lineData = Data(line)
            if let event = try? decoder.decode(EncodedEvent.self, from: lineData) {
                out.append((lineData, event.eventTS))
            }
        }
        return out
    }

    /// Drops TTL-expired and over-cap entries, rewrites the file if anything
    /// changed, and returns the surviving entries. Updates `cachedCount`.
    @discardableResult
    private func pruneLocked(now: Date) -> [(Data, Int64)] {
        var entries = readAllLocked()
        let before = entries.count

        let cutoffMs = Int64((now.timeIntervalSince1970 - config.maxAgeSeconds) * 1000)
        entries.removeAll { $0.1 < cutoffMs }
        if entries.count > config.maxEvents {
            entries.removeFirst(entries.count - config.maxEvents)
        }

        let removed = before - entries.count
        if removed > 0 {
            evictedCount += removed
            writeAllLocked(entries)
        }
        cachedCount = entries.count
        return entries
    }

    private func writeAllLocked(_ entries: [(Data, Int64)]) {
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        var blob = Data()
        for (line, _) in entries {
            blob.append(line)
            blob.append(UInt8(ascii: "\n"))
        }
        // Atomic replace (temp + rename) so a crash mid-write can't corrupt the
        // queue — the old file stays intact until the rename commits.
        try? blob.write(to: fileURL, options: [.atomic])
    }
}
