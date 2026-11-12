import Foundation
import Sparkle
import XCTest
@testable import Suniye

@MainActor
final class UpdateServiceMoreTests: XCTestCase {
    private static let sparkleDefaultsKeys = [
        "SUEnableAutomaticChecks",
        "SUAutomaticallyUpdate",
        "SUScheduledCheckInterval",
    ]

    private func preserveSparkleDefaults() {
        let defaults = UserDefaults.standard
        let savedValues = Self.sparkleDefaultsKeys.map { ($0, defaults.object(forKey: $0)) }
        addTeardownBlock {
            for (key, value) in savedValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }

    func testUpdateChannelChangeNotifiesOnlyOnActualChange() {
        let controller = SparkleUpdateController()
        var stateChanges = 0
        controller.onStateChange = { stateChanges += 1 }

        controller.updateChannel = .stable
        XCTAssertEqual(stateChanges, 0)

        controller.updateChannel = .tip
        XCTAssertEqual(stateChanges, 1)
        XCTAssertEqual(controller.updateChannel, .tip)
    }

    func testAutomaticallyChecksForUpdatesWritesThroughAndNotifies() {
        preserveSparkleDefaults()

        let controller = SparkleUpdateController()
        var stateChanges = 0
        controller.onStateChange = { stateChanges += 1 }

        controller.automaticallyChecksForUpdates = false
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
        XCTAssertEqual(stateChanges, 1)

        controller.automaticallyChecksForUpdates = true
        XCTAssertTrue(controller.automaticallyChecksForUpdates)
        XCTAssertEqual(stateChanges, 2)
    }

    func testStagedUpdateInstallsUntilItsUpdateCycleEnds() {
        let controller = SparkleUpdateController()
        let updater = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        ).updater
        var stateChanges = 0
        var installs = 0
        controller.onStateChange = { stateChanges += 1 }

        controller.installUpdateAndRelaunch()
        XCTAssertFalse(controller.isUpdateReadyToInstall)
        XCTAssertEqual(installs, 0)

        let handledByApp = controller.updater(
            updater,
            willInstallUpdateOnQuit: SUAppcastItem.empty(),
            immediateInstallationBlock: { installs += 1 }
        )
        XCTAssertTrue(handledByApp)
        XCTAssertTrue(controller.isUpdateReadyToInstall)
        XCTAssertEqual(stateChanges, 1)

        controller.installUpdateAndRelaunch()
        XCTAssertEqual(installs, 1)

        controller.updater(updater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)
        XCTAssertFalse(controller.isUpdateReadyToInstall)
        XCTAssertEqual(stateChanges, 2)

        controller.installUpdateAndRelaunch()
        XCTAssertEqual(installs, 1)
    }

    func testSparkleDelegateExposesChannelConfiguration() {
        let controller = SparkleUpdateController()
        let updater = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        ).updater

        XCTAssertEqual(controller.allowedChannels(for: updater), [])
        XCTAssertEqual(controller.feedURLString(for: updater), "https://suniye.kishans.in/appcast.xml")

        controller.updateChannel = .tip
        XCTAssertEqual(controller.allowedChannels(for: updater), ["tip"])
        XCTAssertEqual(controller.feedURLString(for: updater), "https://suniye.kishans.in/appcast-tip.xml")
    }
}
