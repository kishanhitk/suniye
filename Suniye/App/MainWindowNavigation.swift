import Foundation

/// What the main window shows, and what Settings keeps between visits: the
/// pane, where Back returns to, the search query and the row pointed at.
struct MainWindowNavigation: Equatable {
    private(set) var selection: MainWindowSection = .dashboard
    var settingsPane: SettingsPane
    private(set) var sectionBeforeSettings: MainWindowSection = .dashboard
    var settingsQuery = ""
    /// Set when something asks for the search box; the sidebar clears it once
    /// the box has the focus.
    var searchFocusPending = false
    private(set) var highlight: SettingsHighlight?

    init(destination: MainWindowDestination, permissionsMissing: Bool) {
        settingsPane = permissionsMissing ? .permissions : .microphone
        open(destination, permissionsMissing: permissionsMissing)
    }

    mutating func open(_ destination: MainWindowDestination, permissionsMissing: Bool) {
        let entersSettings = destination.section == .settings && selection != .settings
        if entersSettings {
            sectionBeforeSettings = selection
            // Settings opens on its panes. ⌘K brings the last search back,
            // selected, so typing starts a new one.
            if !destination.focusesSearch {
                settingsQuery = ""
            }
        }
        if let pane = destination.pane {
            settingsPane = Self.listed(pane, permissionsMissing: permissionsMissing)
        } else if entersSettings {
            // Permissions first while a grant is missing, so the blocker is the
            // first thing Settings shows.
            settingsPane = permissionsMissing ? .permissions : Self.listed(settingsPane, permissionsMissing: false)
        }
        if destination.focusesSearch {
            searchFocusPending = true
        }
        selection = destination.section
        highlight = destination.row.map { SettingsHighlight(row: $0) }
    }

    /// The Permissions pane leaves the list once every grant is in.
    mutating func permissionsChanged(missing: Bool) {
        settingsPane = Self.listed(settingsPane, permissionsMissing: missing)
    }

    /// Ends a highlight, unless a newer opening has replaced it.
    mutating func endHighlight(_ opened: SettingsHighlight) {
        if highlight == opened {
            highlight = nil
        }
    }

    private static func listed(_ pane: SettingsPane, permissionsMissing: Bool) -> SettingsPane {
        pane == .permissions && !permissionsMissing ? .microphone : pane
    }
}
