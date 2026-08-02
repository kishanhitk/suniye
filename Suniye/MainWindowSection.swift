import Foundation

enum MainWindowSection: String, CaseIterable, Hashable, Codable {
    case dashboard
    case computerUse
    case history
    case model
    case style
    case general

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .computerUse:
            return "Computer Use"
        case .history:
            return "History"
        case .model:
            return "Model"
        case .style:
            return "Magic Format"
        case .general:
            return "General"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2"
        case .computerUse:
            return "cursorarrow.click.2"
        case .history:
            return "clock"
        case .model:
            return "cpu"
        case .style:
            return "sparkles"
        case .general:
            return "gearshape"
        }
    }

    var launchArgument: String {
        switch self {
        case .computerUse:
            return "--open-computer-use"
        default:
            return "--open-\(rawValue)"
        }
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

        if arguments.contains("--open-vocabulary") || arguments.contains("--open-llm") {
            return .style
        }

        return .dashboard
    }
}
