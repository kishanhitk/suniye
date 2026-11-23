import Foundation

/// The panes of Settings, in sidebar order.
enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    /// Listed only while a grant is missing.
    case permissions
    case microphone
    case shortcuts
    case indicator
    case speechModel
    case meetings
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .permissions:
            return "Permissions"
        case .microphone:
            return "Microphone"
        case .shortcuts:
            return "Shortcuts"
        case .indicator:
            return "Indicator"
        case .speechModel:
            return "Speech model"
        case .meetings:
            return "Meetings"
        case .general:
            return "General"
        }
    }

    var icon: String {
        switch self {
        case .permissions:
            return "lock.shield"
        case .microphone:
            return "mic"
        case .shortcuts:
            return "keyboard"
        case .indicator:
            return "capsule"
        case .speechModel:
            return "cpu"
        case .meetings:
            return "person.2"
        case .general:
            return "gearshape"
        }
    }

    static func listed(permissionsMissing: Bool) -> [SettingsPane] {
        permissionsMissing ? allCases : allCases.filter { $0 != .permissions }
    }
}
