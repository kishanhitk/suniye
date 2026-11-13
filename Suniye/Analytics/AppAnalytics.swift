import Foundation
import SuniyeAnalytics

/// Builds the production `Analytics` client for the app: resolves the ingest
/// endpoint from Info.plist, wires the durable queue + settings store, and
/// assembles the anonymous identity. Returns a `NoopAnalytics` if no endpoint is
/// configured, so the app is unaffected when analytics is not set up.
enum AppAnalytics {
    static func makeDefault() -> Analytics {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "SuniyeAnalyticsEndpointURL") as? String,
            case let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty,
            let endpoint = URL(string: trimmed)
        else {
            return NoopAnalytics()
        }

        let store = AnalyticsSettingsStore()
        let settings = store.loadOrCreate()
        let queue = EventQueue(fileURL: queueURL())
        let uploader = AnalyticsUploader(endpoint: endpoint)

        let version = AppVersion.fromBundle()
        let identity = AnalyticsIdentity(
            installID: settings.installID,
            appVersion: version.map { "\($0.marketing.major).\($0.marketing.minor).\($0.marketing.patch)" } ?? "0",
            build: version?.build.map(String.init) ?? "0",
            channel: (version?.channel ?? .stable).rawValue,
            isDebug: isDebugBuild(),
            device: DeviceProfileReader.read()
        )

        return AnalyticsClient(identity: identity, store: store, queue: queue, uploader: uploader)
    }

    static func queueURL() -> URL {
        AppSupportDirectory.urlOrTemporary()
            .appendingPathComponent("analytics", isDirectory: true)
            .appendingPathComponent("queue.jsonl")
    }

    /// Debug/dev builds and test runs are excluded from analytics entirely.
    static func isDebugBuild() -> Bool {
        if ProcessInfo.processInfo.isRunningUnderXCTest {
            return true
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
