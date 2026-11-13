import Foundation

enum AttentionSeverity: String {
    case error
    case warning
}

enum AttentionItemFixAction: Equatable {
    case requestMicrophonePermission
    case requestAccessibilityPermission

    var title: String {
        switch self {
        case .requestMicrophonePermission, .requestAccessibilityPermission:
            return "Grant Access"
        }
    }
}

struct AttentionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let severity: AttentionSeverity
    let recommendedSection: MainWindowSection
    let fixAction: AttentionItemFixAction?

    var fixTitle: String? {
        fixAction?.title
    }

    init(id: String, title: String, detail: String, severity: AttentionSeverity, recommendedSection: MainWindowSection, fixAction: AttentionItemFixAction? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.recommendedSection = recommendedSection
        self.fixAction = fixAction
    }
}

enum MagicFormatSetupState: Equatable {
    case off
    case needsAPIKey
    case needsServiceSetup
    case ready

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .needsAPIKey:
            return "Needs API key"
        case .needsServiceSetup:
            return "Needs service setup"
        case .ready:
            return "Ready"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Turn it on to improve dictation before text is pasted."
        case .needsAPIKey:
            return "Add an API key to start using Magic Format."
        case .needsServiceSetup:
            return "Finish the service setup above."
        case .ready:
            return "Magic Format is ready to improve your text before it is pasted."
        }
    }

    var icon: String {
        switch self {
        case .off:
            return "pause.circle"
        case .needsAPIKey, .needsServiceSetup:
            return "exclamationmark.circle"
        case .ready:
            return "checkmark.circle.fill"
        }
    }
}

struct MagicFormatSetupTestResult: Equatable {
    enum Severity: Equatable {
        case success
        case error    }

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

struct ASRModelBannerState: Equatable {
    enum Tone: Equatable {
        case info
        case error
        var icon: String {
            switch self {
            case .info:
                return "arrow.triangle.2.circlepath.circle.fill"
            case .error:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    let title: String
    let detail: String
    let tone: Tone
    let progress: Double?
}
