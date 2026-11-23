import Foundation

/// Where an action sends the main window.
enum MainWindowDestination: Equatable {
    /// A page of the main window.
    case section(MainWindowSection)
    /// Settings at a pane. Without one, Settings picks: Permissions while a
    /// grant is missing, otherwise the pane used last.
    case settings(SettingsPane? = nil)
    /// Settings with the search box focused.
    case settingsSearch
    /// The pane or page that holds a settings row, with the row pointed at.
    case row(SettingsRowID)

    var section: MainWindowSection {
        switch self {
        case let .section(section):
            return section
        case .settings, .settingsSearch:
            return .settings
        case let .row(row):
            return row.place == .magicFormat ? .style : .settings
        }
    }

    var pane: SettingsPane? {
        switch self {
        case let .settings(pane):
            return pane
        case let .row(row):
            if case let .pane(pane) = row.place {
                return pane
            }
            return nil
        case .section, .settingsSearch:
            return nil
        }
    }

    var row: SettingsRowID? {
        if case let .row(row) = self {
            return row
        }
        return nil
    }

    var focusesSearch: Bool {
        self == .settingsSearch
    }

    static func initial(arguments: [String]) -> MainWindowDestination {
        for pane in SettingsPane.allCases where arguments.contains(pane.launchArgument) {
            return .settings(pane)
        }

        for section in MainWindowSection.allCases where arguments.contains(section.launchArgument) {
            return section == .settings ? .settings() : .section(section)
        }

        if arguments.contains("--open-history") {
            return .section(.dashboard)
        }

        if arguments.contains("--open-vocabulary") || arguments.contains("--open-llm") {
            return .section(.style)
        }

        return .section(.dashboard)
    }
}
