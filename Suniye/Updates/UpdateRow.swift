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
    var help: String?
}

extension AppState {
    var updateRow: UpdateRow {
        let version = AppVersion.fromBundle()
        guard updatesEnabled else {
            return UpdateRow(title: version?.displayString ?? "Unknown", tone: .quiet, help: "Updates are off in this build.")
        }
        let check: UpdateRow.Action? = canCheckForUpdates ? .check : nil
        switch updateStatus {
        case .idle:
            return UpdateRow(
                title: version?.shortDisplayString ?? "Unknown",
                actionTitle: "Check for updates",
                tone: .quiet,
                action: check,
                help: version?.helpString
            )
        case .checking:
            return UpdateRow(title: "Checking…", symbol: .progress, tone: .quiet)
        case .upToDate:
            return UpdateRow(
                title: "Up to date",
                actionTitle: "Check for updates",
                symbol: .upToDate,
                tone: .plain,
                action: check,
                help: version?.helpString
            )
        case let .available(newVersion), let .readyInSparkleWindow(newVersion):
            // Sparkle's window holds a ready update and asks for the restart itself.
            return UpdateRow(
                title: "Update available",
                symbol: .available,
                tone: .plain,
                action: canCheckForUpdates ? .showUpdate : nil,
                help: "Version \(newVersion) is available."
            )
        case let .downloading(newVersion):
            return UpdateRow(title: "Downloading…", symbol: .progress, tone: .quiet, help: "Downloading version \(newVersion).")
        case let .preparing(newVersion):
            return UpdateRow(title: "Preparing…", symbol: .progress, tone: .quiet, help: "Preparing version \(newVersion).")
        case let .readyToInstall(newVersion):
            return UpdateRow(
                title: "Restart to update",
                symbol: .ready,
                tone: .strong,
                action: .restart,
                isEnabled: canRestartToUpdate,
                help: canRestartToUpdate
                    ? "Installs \(newVersion) and opens \(AppIdentity.current.displayName) again."
                    : "Available after the dictation."
            )
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
            return UpdateRow(
                title: "Offline",
                actionTitle: "Try again",
                symbol: .warning,
                tone: .warning,
                action: check,
                help: "No internet connection."
            )
        case let .checkFailed(message):
            return UpdateRow(title: "Check failed", actionTitle: "Try again", symbol: .warning, tone: .warning, action: check, help: message)
        case let .updateFailed(message):
            return UpdateRow(
                title: "Update failed",
                actionTitle: "Try again",
                symbol: .warning,
                tone: .warning,
                action: canCheckForUpdates ? .showUpdate : nil,
                help: message
            )
        case let .readOnlyLocation(message):
            return UpdateRow(title: "Move to Applications", symbol: .warning, tone: .warning, help: message)
        case let .unsupported(message):
            return UpdateRow(title: "Can’t update", symbol: .warning, tone: .warning, help: message)
        }
    }
}
