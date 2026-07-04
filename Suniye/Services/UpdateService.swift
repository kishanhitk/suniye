import Combine
import Foundation
import Sparkle

@MainActor
protocol AppUpdateControllerProtocol: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var updateChannel: UpdateChannel { get set }
    var onStateChange: (() -> Void)? { get set }

    func start()
    func checkForUpdates()
}

@MainActor
final class SparkleUpdateController: NSObject, AppUpdateControllerProtocol, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController!
    private var canCheckForUpdatesObservation: AnyCancellable?
    private var hasStarted = false

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
