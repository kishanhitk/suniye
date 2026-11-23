import Foundation

enum MainWindowSection: String, CaseIterable, Hashable, Codable {
    /// Transcripts, formerly split across a Dashboard and a History page. The raw
    /// value stays `dashboard` so stored selections and `--open-dashboard` keep
    /// working.
    case dashboard
    case meetings
    case style
    /// Opens the Settings panes in place of the section list.
    case settings

    var title: String {
        switch self {
        case .dashboard:
            return "Transcripts"
        case .meetings:
            return "Meetings"
        case .style:
            return "Magic Format"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "text.alignleft"
        case .meetings:
            return "person.2"
        case .style:
            return "sparkles"
        case .settings:
            return "gearshape"
        }
    }

    var launchArgument: String {
        "--open-\(rawValue)"
    }

    var accessibilityIdentifier: String {
        "main-window-section-\(rawValue)"
    }
}
