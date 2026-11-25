import Foundation

/// The update row in the sidebar footer: what it says, and what a click does.
struct UpdateRow: Equatable {
    enum Symbol: Equatable {
        case progress
        case upToDate
        case available
        case ready
        case warning
    }

    enum Tone: Equatable {
        case quiet
        case plain
        case strong
        case warning
    }

    enum Action: Equatable {
        /// Checks with no window. The answer shows in the row.
        case check
        /// Opens Sparkle's window, which shows the update.
        case showUpdate
        case restart
    }

    var title: String
    /// The title while the pointer is on the row, when `title` does not
    /// already say what a click does.
    var actionTitle: String?
    var symbol: Symbol?
    var tone: Tone
    /// nil when a click does nothing.
    var action: Action?
    /// False while the action waits, such as a restart during a dictation.
    var isEnabled = true
    /// Only for a reason that the title cannot hold.
    var help: String?
}

extension AppState {
    var updateRow: UpdateRow {
        let version = AppVersion.fromBundle()
        guard updatesEnabled else {
            return UpdateRow(title: version?.displayString ?? "Unknown", tone: .quiet)
        }
        let check: UpdateRow.Action? = canCheckForUpdates ? .check : nil
        switch updateStatus {
        case .idle:
            return UpdateRow(title: version?.shortDisplayString ?? "Unknown", actionTitle: "Check for updates", tone: .quiet, action: check)
        case .checking:
            return UpdateRow(title: "Checking…", symbol: .progress, tone: .quiet)
        case .upToDate:
            return UpdateRow(title: "Up to date", actionTitle: "Check for updates", symbol: .upToDate, tone: .plain, action: check)
        case .available, .readyInSparkleWindow:
            // Sparkle's window holds a ready update and asks for the restart itself.
            return UpdateRow(title: "Update available", symbol: .available, tone: .plain, action: canCheckForUpdates ? .showUpdate : nil)
        case .downloading:
            return UpdateRow(title: "Downloading…", symbol: .progress, tone: .quiet)
        case .preparing:
            return UpdateRow(title: "Preparing…", symbol: .progress, tone: .quiet)
        case .readyToInstall:
            return UpdateRow(title: "Restart to update", symbol: .ready, tone: .strong, action: .restart, isEnabled: canRestartToUpdate)
        case .restarting:
            return UpdateRow(title: "Restarting…", symbol: .progress, tone: .quiet)
        case let .problem(problem):
            return row(for: problem, check: check)
        }
    }

    /// The click on the update row.
    func performUpdateRowAction() {
        let row = updateRow
        guard row.isEnabled, let action = row.action else {
            return
        }
        switch action {
        case .check:
            checkForUpdatesQuietly()
        case .showUpdate:
            checkForUpdates()
        case .restart:
            restartToUpdate()
        }
    }

    private func row(for problem: UpdateProblem, check: UpdateRow.Action?) -> UpdateRow {
        switch problem {
        case .offline:
            return UpdateRow(title: "Offline", actionTitle: "Try again", symbol: .warning, tone: .warning, action: check)
        case .checkFailed:
            return UpdateRow(title: "Check failed", actionTitle: "Try again", symbol: .warning, tone: .warning, action: check)
        case .updateFailed:
            return UpdateRow(
                title: "Update failed",
                actionTitle: "Try again",
                symbol: .warning,
                tone: .warning,
                action: canCheckForUpdates ? .showUpdate : nil
            )
        case .readOnlyLocation:
            return UpdateRow(title: "Move to Applications", symbol: .warning, tone: .warning)
        case let .unsupported(reason):
            return UpdateRow(title: "Can’t update", symbol: .warning, tone: .warning, help: reason)
        }
    }
}
