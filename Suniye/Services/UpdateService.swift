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
