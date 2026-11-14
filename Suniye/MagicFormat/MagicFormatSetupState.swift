import Foundation

enum MagicFormatSetupState: Equatable {
    case off
    case needsAPIKey
    case needsServiceSetup
    case ready
}

struct MagicFormatSetupTestResult: Equatable {
    enum Severity: Equatable {
        case success
        case error
    }

    let message: String
    let severity: Severity
    /// Round trip for the test request. Already measured for the log line; a
    /// successful test that also reports how long it took answers "is this fast
    /// enough to sit in my dictation path?" at the moment the user asks it.
    var latencyMs: Int?

    /// "Latency 840 ms" / "Latency 1.2 s".
    var latencyText: String? {
        guard let latencyMs, severity == .success else {
            return nil
        }
        if latencyMs < 1000 {
            return "Latency \(latencyMs) ms"
        }
        return "Latency \(String(format: "%.1f", Double(latencyMs) / 1000)) s"
    }
}
