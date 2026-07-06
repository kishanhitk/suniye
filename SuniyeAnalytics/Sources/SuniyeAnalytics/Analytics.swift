import Foundation

/// The app's entire dependency on analytics. There is deliberately no
/// `track(name:properties:)` — only the closed `AnalyticsEvent` set — so callers
/// cannot invent events or attach free text.
public protocol Analytics: Sendable {
    /// Record an event. Non-blocking, best-effort, never throws. A no-op when
    /// disabled, in a debug build, or remotely killed.
    func track(_ event: AnalyticsEvent)

    /// Turn emission on/off (the user's opt-out). Disabling drops any unsent
    /// queued events.
    func setEnabled(_ enabled: Bool)

    /// Force-send queued events now (called on quit/sleep). Awaitable so the app
    /// can give it a moment before terminating.
    func flush() async

    /// Start the periodic flush/health timer. Call once after construction.
    func start()

    /// Stop the timer.
    func stop()

    /// Synchronously enqueue a `session_end` event (durably persisted) WITHOUT
    /// awaiting a flush — safe to call from `applicationWillTerminate`, where the
    /// process may exit before any async work runs. The event ships next launch.
    func recordSessionEnd(cleanExit: Bool)

    /// Enqueue `session_end` and flush. Use where awaiting is possible (sleep).
    func endSession(cleanExit: Bool) async
}

/// A no-op analytics sink for tests and for builds where analytics is compiled
/// out entirely.
public struct NoopAnalytics: Analytics {
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
    public func setEnabled(_ enabled: Bool) {}
    public func flush() async {}
    public func start() {}
    public func stop() {}
    public func recordSessionEnd(cleanExit: Bool) {}
    public func endSession(cleanExit: Bool) async {}
}
