import Foundation

/// Durable, append-only offline queue backed by a JSONL file.
///
/// Every `append` is flushed to disk synchronously (fsync) before returning, so
/// events survive an abrupt termination — a resident menu-bar app gets no clean
/// shutdown on force-quit/crash, so we can't rely on a graceful flush. Bounded
/// by count and age; overflow drops the oldest and is surfaced as an eviction
/// count (reported via an `analytics_health` event).
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

    /// Total events dropped by TTL/size eviction since the last read of this
    /// counter. Consumed by the client to emit `analytics_health`.
    private var evictedCount = 0

    public init(fileURL: URL, config: Config = Config()) {
        self.fileURL = fileURL
        self.config = config
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Persists one event durably. Enforces size/age bounds.
    public func append(_ event: EncodedEvent, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        guard let line = try? encoder.encode(event) else { return }
        var events = readAllLocked()
        events.append((line, event.eventTS))
        pruneLocked(&events, now: now)
        writeAllLocked(events)
    }

    /// Returns up to `max` oldest events for sending, without removing them.
    public func peek(max: Int) -> [EncodedEvent] {
        lock.lock()
        defer { lock.unlock() }
        let lines = readAllLocked().prefix(max)
        return lines.compactMap { try? decoder.decode(EncodedEvent.self, from: $0.0) }
    }

    /// Removes the oldest `count` events after a successful send.
    public func removeOldest(_ count: Int) {
        guard count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        var events = readAllLocked()
        events.removeFirst(min(count, events.count))
        writeAllLocked(events)
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return readAllLocked().count
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

    private func pruneLocked(_ events: inout [(Data, Int64)], now: Date) {
        let cutoffMs = Int64((now.timeIntervalSince1970 - config.maxAgeSeconds) * 1000)
        let beforeAge = events.count
        events.removeAll { $0.1 < cutoffMs }
        evictedCount += beforeAge - events.count

        if events.count > config.maxEvents {
            let overflow = events.count - config.maxEvents
            events.removeFirst(overflow)
            evictedCount += overflow
        }
    }

    private func writeAllLocked(_ events: [(Data, Int64)]) {
        if events.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        var blob = Data()
        for (line, _) in events {
            blob.append(line)
            blob.append(UInt8(ascii: "\n"))
        }
        // Atomic replace + fsync so a crash mid-write can't corrupt the queue.
        do {
            try blob.write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort: analytics must never throw into the app.
        }
    }
}
