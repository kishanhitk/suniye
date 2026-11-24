import Foundation

/// The production `Analytics` implementation: stamps identity/timestamps,
/// manages sessions, buffers to the durable queue, and uploads in batches with
/// the conservative retry policy. Safe to call `track` from any thread.
public final class AnalyticsClient: Analytics, @unchecked Sendable {
    private enum Limits {
        static let flushThreshold = 25
        /// Max events per upload request (also stays under AE's 250/invocation).
        static let maxBatchSize = 25
        static let flushInterval: TimeInterval = 60
        /// New session id after this much inactivity.
        static let sessionGap: TimeInterval = 5 * 60
    }

    private let identity: AnalyticsIdentity
    private let store: AnalyticsSettingsStore
    private let queue: EventQueue
    private let uploader: AnalyticsUploader
    /// Runs queue persistence (disk I/O) off the caller thread. `track` is called
    /// from the main actor during dictation, so the fsync'd append must not block
    /// it. Serial → FIFO event order.
    private static let persistQueue = DispatchQueue(
        label: "dev.suniye.analytics.persist", qos: .utility
    )

    private let lock = NSLock()
    private var enabled: Bool
    private var directive: KillSwitchDirective?
    private var sessionID: String
    private var lastActivityAt: Date
    private var sessionEventCount = 0
    private var sessionStartedAt: Date
    private var uploadFailures = 0
    private var isFlushing = false
    private var timerTask: Task<Void, Never>?

    public init(
        identity: AnalyticsIdentity,
        store: AnalyticsSettingsStore,
        queue: EventQueue,
        uploader: AnalyticsUploader
    ) {
        self.identity = identity
        self.store = store
        self.queue = queue
        self.uploader = uploader

        let settings = store.loadOrCreate()
        self.enabled = settings.enabled
        self.directive = store.loadDirective()
        let start = Date()
        self.sessionID = UUID().uuidString
        self.lastActivityAt = start
        self.sessionStartedAt = start
    }

    // MARK: - Analytics

    public func track(_ event: AnalyticsEvent) {
        lock.lock()
        guard emittingLocked() else { lock.unlock(); return }
        if let rate = directive?.sampleRate, Double.random(in: 0..<1) >= rate {
            lock.unlock(); return
        }

        let current = Date()
        if current.timeIntervalSince(lastActivityAt) > Limits.sessionGap {
            sessionID = UUID().uuidString
            sessionStartedAt = current
            sessionEventCount = 0
        }
        lastActivityAt = current
        sessionEventCount += 1
        let session = sessionID
        let encoded = EncodedEvent(
            event: event,
            eventID: UUID().uuidString,
            eventTS: Int64(current.timeIntervalSince1970 * 1000),
            sessionID: session
        )
        lock.unlock()

        // The append fsyncs, and `track` runs on the main actor during dictation.
        Self.persistQueue.async { [self] in
            queue.append(encoded, now: current)
            if queue.count >= Limits.flushThreshold {
                Task { await self.flush() }
            }
        }
    }

    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        lock.unlock()
        store.setEnabled(enabled)
        if !enabled {
            // Route through `persist` so the drop happens-after any queued
            // appends (FIFO) — an opt-out clears events still in flight too.
            Self.persistQueue.async { [self] in queue.removeAll() }
        }
    }

    public func flush() async {
        guard beginFlush() else { return }
        defer { endFlush() }

        while true {
            let events = queue.peek(max: Limits.maxBatchSize, now: Date())
            if events.isEmpty { break }

            let outcome = await uploader.upload(makeBatch(events))
            switch outcome {
            case let .accepted(directive):
                queue.removeOldest(events.count)
                if let directive { apply(directive) }
                continue
            case .rejected, .ambiguous:
                queue.removeOldest(events.count)   // drop poison / avoid double-count
                bumpFailures()
                return
            case .retry:
                bumpFailures()
                return
            }
        }
    }

    // MARK: - Lifecycle

    public func start() {
        stop()
        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let interval = Limits.flushInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                self.emitHealthIfNeeded()
                await self.flush()
            }
        }
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Persists `session_end` at once and does not flush; safe at termination.
    public func recordSessionEnd(cleanExit: Bool) {
        let (duration, eventCount) = sessionSummary()
        track(.sessionEnd(durationMs: duration, eventCount: eventCount, cleanExit: cleanExit))
    }

    public func endSession(cleanExit: Bool) async {
        recordSessionEnd(cleanExit: cleanExit)
        await flush()
    }

    public var installID: String { identity.installID }

    // MARK: - Internals

    private func emittingLocked() -> Bool {
        enabled && !identity.isDebug && !(directive?.disabled ?? false)
    }

    /// Acquires the flush slot (no-op if disabled or already flushing).
    /// Synchronous so the lock is never held across an `await`.
    private func beginFlush() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard emittingLocked(), !isFlushing else { return false }
        isFlushing = true
        return true
    }

    private func endFlush() {
        lock.lock(); isFlushing = false; lock.unlock()
    }

    private func sessionSummary() -> (durationMs: Int, eventCount: Int) {
        lock.lock(); defer { lock.unlock() }
        return (Int(Date().timeIntervalSince(sessionStartedAt) * 1000), sessionEventCount)
    }

    private func makeBatch(_ events: [EncodedEvent]) -> AnalyticsBatch {
        AnalyticsBatch(
            schemaVersion: analyticsSchemaVersion,
            installID: identity.installID,
            appVersion: identity.appVersion,
            build: identity.build,
            channel: identity.channel,
            isDebug: identity.isDebug,
            sentAt: Int64(Date().timeIntervalSince1970 * 1000),
            device: identity.device?.batchProps,
            events: events
        )
    }

    private func apply(_ directive: KillSwitchDirective) {
        lock.lock()
        self.directive = directive
        lock.unlock()
        store.saveDirective(directive)
    }

    private func bumpFailures() {
        lock.lock(); uploadFailures += 1; lock.unlock()
    }

    private func emitHealthIfNeeded() {
        let evicted = queue.takeEvictedCounts()
        lock.lock()
        let failures = uploadFailures
        uploadFailures = 0
        let depth = queue.count
        lock.unlock()
        guard evicted.ttl > 0 || evicted.size > 0 || failures > 0 else { return }
        track(.analyticsHealth(
            queueDepth: depth,
            uploadFailures: failures,
            evictedByTTL: evicted.ttl,
            evictedBySize: evicted.size
        ))
    }
}
