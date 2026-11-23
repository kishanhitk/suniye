import Foundation

/// Where an action sends the main window: a section and, inside Settings, a
/// pane. A row is pointed at for a moment after it opens.
struct MainWindowDestination: Equatable {
    let section: MainWindowSection
    var pane: SettingsPane?
    var row: SettingsRowID?
    var focusesSearch = false

    static func section(_ section: MainWindowSection) -> MainWindowDestination {
        MainWindowDestination(section: section)
    }

    /// Without a pane, Settings picks one: Permissions while a grant is
    /// missing, otherwise the pane used last.
    static func settings(_ pane: SettingsPane? = nil) -> MainWindowDestination {
        MainWindowDestination(section: .settings, pane: pane)
    }

    static let settingsSearch = MainWindowDestination(section: .settings, focusesSearch: true)

    static func row(_ row: SettingsRowID) -> MainWindowDestination {
        switch row.place {
        case let .pane(pane):
            return MainWindowDestination(section: .settings, pane: pane, row: row)
        case .magicFormat:
            return MainWindowDestination(section: .style, row: row)
        }
    }

    static func initial(arguments: [String]) -> MainWindowDestination {
        for section in MainWindowSection.allCases where arguments.contains(section.launchArgument) {
            return .section(section)
        }

        // Speech Model and General were sections before they became panes.
        if arguments.contains("--open-model") {
            return .settings(.speechModel)
        }

        if arguments.contains("--open-general") {
            return .settings(.general)
        }

        // History merged into Transcripts; the old argument still has to work.
        if arguments.contains("--open-history") {
            return .section(.dashboard)
        }

        if arguments.contains("--open-vocabulary") || arguments.contains("--open-llm") {
            return .section(.style)
        }

        return .section(.dashboard)
    }
}
