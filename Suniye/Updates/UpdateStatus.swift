import Foundation

/// A step of an update, as Sparkle reports it.
enum AppUpdateEvent: Equatable {
    /// Sparkle offers this version and does not install it on its own.
    case available(version: String)
    case downloading(version: String)
    case preparing(version: String)
    /// Sparkle's own window offers to install and relaunch.
    case readyInSparkleWindow(version: String)
    /// The update is downloaded, and a restart installs it.
    case readyToInstall(version: String)
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
    case unsupported(message: String)
}

struct UpdateFailure: Equatable {
    enum Kind: Equatable {
        case offline
        /// The app runs from a disk image or another place Sparkle cannot replace it in.
        case readOnlyLocation
        case other
    }

    let kind: Kind
    /// Sparkle's description of the failure.
    let message: String
}

/// What the sidebar footer shows about updates.
enum UpdateStatus: Equatable {
    case idle
    /// A check that the user started from the footer.
    case checking
    case upToDate
    case available(version: String)
    case downloading(version: String)
    case preparing(version: String)
    case readyInSparkleWindow(version: String)
    case readyToInstall(version: String)
    case restarting(version: String)
    case problem(UpdateProblem)

    var isReadyToInstall: Bool {
        switch self {
        case .readyToInstall, .restarting:
            return true
        default:
            return false
        }
    }

    /// The status after Sparkle reports `event`. A failure shows only when it
    /// ends what the footer shows: a check the user started, or an update on
    /// its way. A scheduled check stays quiet, and the next one tries again.
    func applying(_ event: AppUpdateEvent) -> UpdateStatus {
        switch event {
        case let .available(version):
            return .available(version: version)
        case let .downloading(version):
            return .downloading(version: version)
        case let .preparing(version):
            return .preparing(version: version)
        case let .readyInSparkleWindow(version):
            return .readyInSparkleWindow(version: version)
        case let .readyToInstall(version):
            return .readyToInstall(version: version)
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

    /// The version of an update on its way, from its download to the restart.
    private var updateInProgress: String? {
        switch self {
        case let .downloading(version), let .preparing(version), let .readyInSparkleWindow(version),
             let .readyToInstall(version), let .restarting(version):
            return version
        case .idle, .checking, .upToDate, .available, .problem:
            return nil
        }
    }

    /// A session that ended with no answer leaves an unfinished update available.
    private var ended: UpdateStatus {
        if self == .checking {
            return .idle
        }
        return updateInProgress.map { .available(version: $0) } ?? self
    }

    private func applying(_ reason: UpdateNotFound) -> UpdateStatus {
        switch self {
        case .checking:
            switch reason {
            case .upToDate:
                return .upToDate
            case let .unsupported(message):
                return .problem(.unsupported(message: message))
            }
        case .available, .problem:
            // A check worked and offers nothing: an earlier offer or failure is stale.
            return .idle
        case .idle, .upToDate, .downloading, .preparing, .readyInSparkleWindow, .readyToInstall, .restarting:
            return ended
        }
    }

    private func applying(_ failure: UpdateFailure) -> UpdateStatus {
        if failure.kind == .readOnlyLocation {
            return .problem(.readOnlyLocation(message: failure.message))
        }
        if self == .checking {
            return failure.kind == .offline ? .problem(.offline) : .problem(.checkFailed(message: failure.message))
        }
        return updateInProgress == nil ? self : .problem(.updateFailed(message: failure.message))
    }
}

enum UpdateProblem: Equatable {
    case offline
    case checkFailed(message: String)
    case updateFailed(message: String)
    case readOnlyLocation(message: String)
    case unsupported(message: String)
}
