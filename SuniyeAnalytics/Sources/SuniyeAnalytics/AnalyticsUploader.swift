import Foundation

/// Result of one batch upload, chosen to avoid over-counting under at-least-once
/// delivery. We only retry when the server *definitely* did not record the
/// batch (couldn't connect, or 5xx before any write). A timeout is ambiguous —
/// the server may have written it — so we drop rather than risk double-counting;
/// `event_id` lets the backend dedup if we ever need exactness.
public enum UploadOutcome: Sendable, Equatable {
    case accepted(KillSwitchDirective?)   // 2xx — remove sent events
    case rejected                         // 4xx — drop (malformed / poison)
    case retry                            // connection failure or 5xx — keep
    case ambiguous                        // timeout — drop to avoid double count
}

public protocol AnalyticsUploading: Sendable {
    func upload(_ batch: AnalyticsBatch) async -> UploadOutcome
}

public struct AnalyticsUploader: AnalyticsUploading {
    private let endpoint: URL
    private let session: URLSession
    private let timeout: TimeInterval

    public init(endpoint: URL, session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.endpoint = endpoint
        self.session = session
        self.timeout = timeout
    }

    public func upload(_ batch: AnalyticsBatch) async -> UploadOutcome {
        guard let body = try? JSONEncoder().encode(batch) else { return .rejected }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Suniye/Analytics", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .ambiguous }
            switch http.statusCode {
            case 200..<300:
                return .accepted(Self.parseDirective(from: data))
            case 400..<500:
                return .rejected
            default:
                return .retry   // 5xx: reached the server but not stored — safe to retry
            }
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .networkConnectionLost, .secureConnectionFailed:
                return .retry   // never reached the server
            case .timedOut:
                return .ambiguous
            default:
                return .ambiguous
            }
        } catch {
            return .ambiguous
        }
    }

    private static func parseDirective(from data: Data) -> KillSwitchDirective? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(KillSwitchDirective.self, from: data)
    }
}
