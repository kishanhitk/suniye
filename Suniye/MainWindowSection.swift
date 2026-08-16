import Foundation

enum MainWindowSection: String, CaseIterable, Hashable, Codable {
    /// Transcripts, formerly split across a Dashboard and a History page. The raw
    /// value stays `dashboard` so stored selections and `--open-dashboard` keep
    /// working.
    case dashboard
    case model
    case style
    case general

    var title: String {
        switch self {
        case .dashboard:
            return "Transcripts"
        case .model:
            return "Speech Model"
        case .style:
            return "Magic Format"
        case .general:
            return "General"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "text.quote"
        case .model:
            return "cpu"
        case .style:
            return "sparkles"
        case .general:
            return "gearshape"
        }
    }

    var launchArgument: String {
        "--open-\(rawValue)"
    }

    var accessibilityIdentifier: String {
        "main-window-section-\(rawValue)"
    }

    static func initialSelection(arguments: [String]) -> MainWindowSection {
        for section in MainWindowSection.allCases where arguments.contains(section.launchArgument) {
            return section
        }

        // History merged into Transcripts; the old argument still has to work.
        if arguments.contains("--open-history") {
            return .dashboard
        }

        if arguments.contains("--open-settings") {
            return .model
        }

        if arguments.contains("--open-vocabulary") || arguments.contains("--open-llm") {
            return .style
        }

        return .dashboard
    }
}
