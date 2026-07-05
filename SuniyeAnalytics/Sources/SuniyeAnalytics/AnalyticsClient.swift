import Foundation

/// The production `Analytics` implementation: stamps identity/timestamps,
/// manages sessions, buffers to the durable queue, and uploads in batches with
/// the conservative retry policy. Safe to call `track` from any thread.
public final class AnalyticsClient: Analytics, @unchecked Sendable {
    public struct Config: Sendable {
        /// Flush once the queue reaches this many events.
        public var flushThreshold: Int
        /// Max events per upload request (also stays under AE's 250/invocation).
        public var maxBatchSize: Int
        /// Periodic flush cadence.
        public var flushInterval: TimeInterval
        /// New session id after this much inactivity.
        public var sessionGap: TimeInterval

        public init(
            flushThreshold: Int = 25,
            maxBatchSize: Int = 25,
            flushInterval: TimeInterval = 60,
            sessionGap: TimeInterval = 5 * 60
        ) {
            self.flushThreshold = flushThreshold
            self.maxBatchSize = maxBatchSize
            self.flushInterval = flushInterval
            self.sessionGap = sessionGap
        }
    }

    private let identity: AnalyticsIdentity
    private let store: AnalyticsSettingsStore
    private let queue: EventQueue
    private let uploader: AnalyticsUploading
    private let config: Config
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String
    private let sampler: @Sendable () -> Double

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
        uploader: AnalyticsUploading,
        config: Config = Config(),
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> String = { UUID().uuidString },
        sampler: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.identity = identity
        self.store = store
        self.queue = queue
        self.uploader = uploader
        self.config = config
        self.now = now
        self.makeID = makeID
        self.sampler = sampler

        let settings = store.loadOrCreate(makeInstallID: makeID, now: now)
        self.enabled = settings.enabled
        self.directive = store.loadDirective()
        let start = now()
        self.sessionID = makeID()
        self.lastActivityAt = start
        self.sessionStartedAt = start
    }

    // MARK: - Analytics

    public func track(_ event: AnalyticsEvent) {
        lock.lock()
        guard emittingLocked() else { lock.unlock(); return }
        if let rate = directive?.sampleRate, sampler() >= rate {
            lock.unlock(); return
        }

        let current = now()
        if current.timeIntervalSince(lastActivityAt) > config.sessionGap {
            sessionID = makeID()
            sessionStartedAt = current
            sessionEventCount = 0
        }
        lastActivityAt = current
        sessionEventCount += 1
        let session = sessionID
        let encoded = EncodedEvent(
            event: event,
            eventID: makeID(),
            eventTS: Int64(current.timeIntervalSince1970 * 1000),
            sessionID: session
        )
        lock.unlock()

        queue.append(encoded, now: current)

        if queue.count >= config.flushThreshold {
            Task { await self.flush() }
        }
    }

    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        lock.unlock()
        store.setEnabled(enabled, makeInstallID: makeID)
        if !enabled {
            queue.removeAll()   // drop unsent events when the user opts out
        }
    }

    public func flush() async {
        guard beginFlush() else { return }
        defer { endFlush() }

        while true {
            let events = queue.peek(max: config.maxBatchSize)
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
                bumpFailures()                     // keep events, try again later
                return
            }
        }
    }

    // MARK: - Lifecycle

    /// Starts the periodic flush/health timer. Call once after construction.
    public func start() {
        stop()
        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let interval = self.config.flushInterval
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

    /// Emits a `session_end` event and flushes. Called on app quit / sleep.
    public func endSession(cleanExit: Bool) async {
        let (duration, eventCount) = sessionSummary()
        track(.sessionEnd(durationMs: duration, eventCount: eventCount, cleanExit: cleanExit))
        await flush()
    }

    /// The current install id (for surfacing in a privacy/settings screen).
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
        return (Int(now().timeIntervalSince(sessionStartedAt) * 1000), sessionEventCount)
    }

    private func makeBatch(_ events: [EncodedEvent]) -> AnalyticsBatch {
        AnalyticsBatch(
            schemaVersion: analyticsSchemaVersion,
            installID: identity.installID,
            appVersion: identity.appVersion,
            build: identity.build,
            channel: identity.channel,
            isDebug: identity.isDebug,
            sentAt: Int64(now().timeIntervalSince1970 * 1000),
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
        let evicted = queue.takeEvictedCount()
        lock.lock()
        let failures = uploadFailures
        uploadFailures = 0
        let depth = queue.count
        lock.unlock()
        guard evicted > 0 || failures > 0 else { return }
        track(.analyticsHealth(queueDepth: depth, uploadFailures: failures, evictedByTTL: evicted))
    }
}
