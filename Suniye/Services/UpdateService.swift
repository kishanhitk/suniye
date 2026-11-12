import Combine
import Foundation
import Sparkle

@MainActor
protocol AppUpdateControllerProtocol: AnyObject {
    var canCheckForUpdates: Bool { get }
    var isUpdateReadyToInstall: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var updateChannel: UpdateChannel { get set }
    var onStateChange: (() -> Void)? { get set }

    func start()
    func checkForUpdates()
    func installUpdateAndRelaunch()
}

@MainActor
final class SparkleUpdateController: NSObject, AppUpdateControllerProtocol, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController!
    private var canCheckForUpdatesObservation: AnyCancellable?
    private var hasStarted = false
    private var installStagedUpdate: (() -> Void)?

    var onStateChange: (() -> Void)?

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

    var isUpdateReadyToInstall: Bool {
        installStagedUpdate != nil
    }

    var automaticallyDownloadsUpdates: Bool {
        updaterController.updater.automaticallyDownloadsUpdates
    }

    var updateCheckInterval: TimeInterval {
        updaterController.updater.updateCheckInterval
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

    func installUpdateAndRelaunch() {
        installStagedUpdate?()
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
        onStateChange?()
        return true
    }

    /// While an update is held, the only cycle that can finish is the one
    /// holding it, so its end means the handler no longer installs anything.
    @objc(updater:didFinishUpdateCycleForUpdateCheck:error:)
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard installStagedUpdate != nil else {
            return
        }
        AppLogger.shared.log(.warning, "sparkle staged update dropped error=\(error?.localizedDescription ?? "none")")
        installStagedUpdate = nil
        onStateChange?()
    }

    @objc(allowedChannelsForUpdater:)
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        updateChannel.sparkleAllowedChannels
    }

    @objc(feedURLStringForUpdater:)
    func feedURLString(for updater: SPUUpdater) -> String? {
        updateChannel.appcastURLString
    }
}

@MainActor
final class DisabledUpdateController: AppUpdateControllerProtocol {
    var canCheckForUpdates: Bool { false }
    var isUpdateReadyToInstall: Bool { false }
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

    func start() {
        onStateChange?()
    }

    func checkForUpdates() {
        onStateChange?()
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
