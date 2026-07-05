import Foundation

/// Current wire schema version. Every batch carries it so the ingest Worker can
/// reject/adapt. Bump only for breaking changes (adding optional fields is not
/// breaking — see AnalyticsEvent).
public let analyticsSchemaVersion = 1

/// One event as persisted to the offline queue and sent on the wire. Carries the
/// per-event identity (`event_id` for at-least-once dedup, `event_ts` client
/// timestamp so time-series survive offline batching) and the session id.
public struct EncodedEvent: Codable, Equatable, Sendable {
    public let eventID: String
    public let eventTS: Int64      // epoch milliseconds, stamped at track time
    public let sessionID: String
    public let name: String
    public let props: [String: AnalyticsValue]

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case eventTS = "event_ts"
        case sessionID = "session_id"
        case name
        case props
    }

    public init(event: AnalyticsEvent, eventID: String, eventTS: Int64, sessionID: String) {
        self.eventID = eventID
        self.eventTS = eventTS
        self.sessionID = sessionID
        self.name = event.name
        self.props = event.props
    }
}

/// The batch envelope POSTed to the ingest Worker. Process-stable fields
/// (install id, app version, channel, is_debug) live here once rather than on
/// every event.
public struct AnalyticsBatch: Encodable, Sendable {
    public let schemaVersion: Int
    public let installID: String
    public let appVersion: String
    public let build: String
    public let channel: String
    public let isDebug: Bool
    public let sentAt: Int64
    public let events: [EncodedEvent]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case installID = "install_id"
        case appVersion = "app_version"
        case build
        case channel
        case isDebug = "is_debug"
        case sentAt = "sent_at"
        case events
    }
}

/// Process-stable identity attached to every batch. Assembled by the app.
public struct AnalyticsIdentity: Sendable, Equatable {
    public let installID: String
    public let appVersion: String
    public let build: String
    public let channel: String
    public let isDebug: Bool

    public init(installID: String, appVersion: String, build: String, channel: String, isDebug: Bool) {
        self.installID = installID
        self.appVersion = appVersion
        self.build = build
        self.channel = channel
        self.isDebug = isDebug
    }
}
