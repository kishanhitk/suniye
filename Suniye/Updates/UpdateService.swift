import Combine
import Foundation
import Sparkle

@MainActor
protocol AppUpdateControllerProtocol: AnyObject {
    /// False in builds that ship without updates, such as Preview.
    var isEnabled: Bool { get }
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var updateChannel: UpdateChannel { get set }
    /// Called when `canCheckForUpdates` or a setting changes.
    var onStateChange: (() -> Void)? { get set }
    /// Called for each update step that Sparkle reports.
    var onEvent: ((AppUpdateEvent) -> Void)? { get set }

    func start()
    /// Opens Sparkle's window: the check, then the release notes and Install.
    func checkForUpdates()
    /// Checks the feed with no window. The answer arrives through `onEvent`.
    /// Returns false when Sparkle cannot start a check now.
    func checkForUpdateInformation() -> Bool
    func installUpdateAndRelaunch()
}

@MainActor
final class SparkleUpdateController: NSObject, AppUpdateControllerProtocol, SPUUpdaterDelegate {
    var isEnabled: Bool { true }
    private var updaterController: SPUStandardUpdaterController!
    private var canCheckForUpdatesObservation: AnyCancellable?
    private var hasStarted = false
    private var installStagedUpdate: (() -> Void)?
    /// The user chose Install in Sparkle's window, so that window, not the app,
    /// offers the restart once the update is extracted.
    private var sparkleWindowInstallsUpdate = false

    var onStateChange: (() -> Void)?
    var onEvent: ((AppUpdateEvent) -> Void)?

    override init() {
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        canCheckForUpdatesObservation = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.onStateChange?()
            }
    }

    var updateChannel: UpdateChannel = .stable {
        didSet {
            guard oldValue != updateChannel else {
                return
            }

            if hasStarted {
                updaterController.updater.resetUpdateCycle()
            }
            onStateChange?()
        }
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            updaterController.updater.automaticallyChecksForUpdates
        }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
            onStateChange?()
        }
    }

    func start() {
        hasStarted = true
        updaterController.startUpdater()
        onStateChange?()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdateInformation() -> Bool {
        let updater = updaterController.updater
        guard hasStarted, !updater.sessionInProgress else {
            return false
        }
        updater.checkForUpdateInformation()
        return true
    }

    func installUpdateAndRelaunch() {
        installStagedUpdate?()
    }

    @objc(updater:didFindValidUpdate:)
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onEvent?(.available)
    }

    @objc(updater:userDidMakeChoice:forUpdate:state:)
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        switch choice {
        case .install:
            sparkleWindowInstallsUpdate = true
        case .skip:
            onEvent?(.skipped)
        case .dismiss:
            break
        @unknown default:
            break
        }
    }

    @objc(updater:willDownloadUpdate:withRequest:)
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        onEvent?(.downloading)
    }

    @objc(updater:willExtractUpdate:)
    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        onEvent?(.preparing)
    }

    /// Sparkle's window shows Install and Relaunch after this. An automatic
    /// update instead reaches `willInstallUpdateOnQuit`.
    @objc(updater:didExtractUpdate:)
    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        if sparkleWindowInstallsUpdate {
            onEvent?(.readyInSparkleWindow)
        }
    }

    /// Returning true keeps Sparkle's update session open, so `handler` stays
    /// valid and no further update checks run until the update installs.
    @objc(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock handler: @escaping () -> Void
    ) -> Bool {
        AppLogger.shared.log(.info, "sparkle update ready to install version=\(item.displayVersionString)")
        installStagedUpdate = handler
        onEvent?(.readyToInstall)
        return true
    }

    /// Every session ends here, with the error that `didAbortWithError` also
    /// gets: the no-update error carries the reason. While an update is held,
    /// the only cycle that can finish is the one holding it, so its end means
    /// the handler no longer installs anything.
    @objc(updater:didFinishUpdateCycleForUpdateCheck:error:)
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        sparkleWindowInstallsUpdate = false
        if installStagedUpdate != nil {
            AppLogger.shared.log(.warning, "sparkle staged update dropped error=\(error?.localizedDescription ?? "none")")
            installStagedUpdate = nil
        }
        let outcome = Self.outcome(of: error.map { $0 as NSError })
        if case let .failed(failure) = outcome {
            AppLogger.shared.log(.warning, "sparkle update failed kind=\(failure) error=\(error?.localizedDescription ?? "none")")
        }
        onEvent?(.finished(outcome))
    }

    @objc(allowedChannelsForUpdater:)
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        updateChannel.sparkleAllowedChannels
    }

    @objc(feedURLStringForUpdater:)
    func feedURLString(for updater: SPUUpdater) -> String? {
        updateChannel.appcastURLString
    }

    private static func outcome(of error: NSError?) -> UpdateOutcome {
        guard let error else {
            return .ended
        }
        if error.domain == SUSparkleErrorDomain {
            switch SUError(rawValue: OSStatus(error.code)) {
            case .noUpdateError:
                return .notFound(notFoundReason(error))
            case .installationCanceledError, .installationAuthorizeLaterError:
                return .ended
            case .runningFromDiskImageError, .runningTranslocated:
                return .failed(.readOnlyLocation)
            default:
                break
            }
        }
        return .failed(isOffline(error) ? .offline : .other)
    }

    private static func notFoundReason(_ error: NSError) -> UpdateNotFound {
        let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)
            .flatMap { SPUNoUpdateFoundReason(rawValue: $0.int32Value) }
        switch reason {
        case .systemIsTooOld, .systemIsTooNew, .hardwareDoesNotSupportARM64:
            return .unsupported(reason: error.localizedRecoverySuggestion ?? error.localizedDescription)
        default:
            return .upToDate
        }
    }

    /// Sparkle wraps the network error of a failed download one or more levels deep.
    private static func isOffline(_ error: NSError) -> Bool {
        let offlineCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDataNotAllowed,
            NSURLErrorInternationalRoamingOff
        ]
        var current: NSError? = error
        while let next = current {
            if next.domain == NSURLErrorDomain, offlineCodes.contains(next.code) {
                return true
            }
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

@MainActor
final class DisabledUpdateController: AppUpdateControllerProtocol {
    var isEnabled: Bool { false }
    var canCheckForUpdates: Bool { false }
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { onStateChange?() }
    }
    var updateChannel: UpdateChannel = .stable {
        didSet {
            guard oldValue != updateChannel else {
                return
            }
            onStateChange?()
        }
    }
    var onStateChange: (() -> Void)?
    var onEvent: ((AppUpdateEvent) -> Void)?

    func start() {
        onStateChange?()
    }

    func checkForUpdates() {
        onStateChange?()
    }

    func checkForUpdateInformation() -> Bool {
        false
    }

    func installUpdateAndRelaunch() {}
}

@MainActor
enum AppUpdateControllerFactory {
    static func makeDefault(updatesEnabled: Bool = Bundle.main.suniyeUpdatesEnabled) -> AppUpdateControllerProtocol {
        updatesEnabled ? SparkleUpdateController() : DisabledUpdateController()
    }
}

extension Bundle {
    var suniyeUpdatesEnabled: Bool {
        guard let value = object(forInfoDictionaryKey: "SuniyeUpdatesEnabled") else {
            return true
        }

        if let enabled = value as? Bool {
            return enabled
        }

        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return true
            }
        }

        return true
    }
}
