import Combine
import Foundation
import Sparkle

@MainActor
protocol AppUpdateControllerProtocol: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var onStateChange: (() -> Void)? { get set }

    func start()
    func checkForUpdates()
}

@MainActor
final class SparkleUpdateController: NSObject, AppUpdateControllerProtocol {
    private let updaterController: SPUStandardUpdaterController
    private var canCheckForUpdatesObservation: AnyCancellable?

    var onStateChange: (() -> Void)?

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        canCheckForUpdatesObservation = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.onStateChange?()
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
        updaterController.startUpdater()
        onStateChange?()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
