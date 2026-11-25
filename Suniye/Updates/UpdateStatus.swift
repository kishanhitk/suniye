import Foundation

/// A step of an update, as Sparkle reports it.
enum AppUpdateEvent: Equatable {
    /// Sparkle offers an update and does not install it on its own.
    case available
    case downloading
    case preparing
    /// Sparkle's own window offers to install and relaunch.
    case readyInSparkleWindow
    /// The update is downloaded, and a restart installs it.
    case readyToInstall
    /// The user skipped this version in Sparkle's window.
    case skipped
    /// Sparkle's update session ended.
    case finished(UpdateOutcome)
}

enum UpdateOutcome: Equatable {
    /// No error: the session offered an update, or the user closed or cancelled it.
    case ended
    case notFound(UpdateNotFound)
    case failed(UpdateFailure)
}

enum UpdateNotFound: Equatable {
    case upToDate
    /// A newer version exists, but this Mac cannot install it.
    case unsupported(reason: String)
}

enum UpdateFailure: Equatable {
    case offline
    /// The app runs from a disk image or another place Sparkle cannot replace it in.
    case readOnlyLocation
    case other
}

/// What the sidebar footer shows about updates.
enum UpdateStatus: Equatable {
    case idle
    /// A check that the user started from the footer.
    case checking
    case upToDate
    case available
    case downloading
    case preparing
    case readyInSparkleWindow
    case readyToInstall
    case restarting
    case problem(UpdateProblem)

    var isReadyToInstall: Bool {
        self == .readyToInstall || self == .restarting
    }

    /// The status after Sparkle reports `event`. A failure shows only when it
    /// ends what the footer shows: a check the user started, or an update on
    /// its way. A scheduled check stays quiet, and the next one tries again.
    func applying(_ event: AppUpdateEvent) -> UpdateStatus {
        switch event {
        case .available:
            return .available
        case .downloading:
            return .downloading
        case .preparing:
            return .preparing
        case .readyInSparkleWindow:
            return .readyInSparkleWindow
        case .readyToInstall:
            return .readyToInstall
        case .skipped:
            return .idle
        case .finished(.ended):
            return ended
        case let .finished(.notFound(reason)):
            return applying(reason)
        case let .finished(.failed(failure)):
            return applying(failure)
        }
    }

    /// An update on its way, from its download to the restart.
    private var isUpdateInProgress: Bool {
        switch self {
        case .downloading, .preparing, .readyInSparkleWindow, .readyToInstall, .restarting:
            return true
        case .idle, .checking, .upToDate, .available, .problem:
            return false
        }
    }

    /// A session that ended with no answer leaves an unfinished update available.
    private var ended: UpdateStatus {
        if self == .checking {
            return .idle
        }
        return isUpdateInProgress ? .available : self
    }

    private func applying(_ reason: UpdateNotFound) -> UpdateStatus {
        switch self {
        case .checking:
            switch reason {
            case .upToDate:
                return .upToDate
            case let .unsupported(text):
                return .problem(.unsupported(reason: text))
            }
        case .available, .problem:
            // A check worked and offers nothing: an earlier offer or failure is stale.
            return .idle
        case .idle, .upToDate, .downloading, .preparing, .readyInSparkleWindow, .readyToInstall, .restarting:
            return ended
        }
    }

    private func applying(_ failure: UpdateFailure) -> UpdateStatus {
        if failure == .readOnlyLocation {
            return .problem(.readOnlyLocation)
        }
        if self == .checking {
            return .problem(failure == .offline ? .offline : .checkFailed)
        }
        return isUpdateInProgress ? .problem(.updateFailed) : self
    }
}

enum UpdateProblem: Equatable {
    case offline
    case checkFailed
    case updateFailed
    case readOnlyLocation
    /// Sparkle's reason, such as a macOS version that is too old.
    case unsupported(reason: String)
}
