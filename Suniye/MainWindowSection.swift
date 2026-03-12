import Foundation

enum MainWindowSection: String, CaseIterable, Hashable, Codable {
    case dashboard
    case history
    case hotkey
    case model
    case vocabulary
    case llm
    case general

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .history:
            return "History"
        case .hotkey:
            return "Hotkey"
        case .model:
            return "Model"
        case .vocabulary:
            return "Vocabulary"
        case .llm:
            return "LLM"
        case .general:
            return "General"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2"
        case .history:
            return "clock"
        case .hotkey:
            return "keyboard"
        case .model:
            return "cpu"
        case .vocabulary:
            return "book.closed"
        case .llm:
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

        if arguments.contains("--open-settings") {
            return .model
        }

        return .dashboard
    }
}
