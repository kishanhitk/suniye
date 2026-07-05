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
}

/// A no-op analytics sink for tests and for builds where analytics is compiled
/// out entirely.
public struct NoopAnalytics: Analytics {
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
    public func setEnabled(_ enabled: Bool) {}
    public func flush() async {}
}
