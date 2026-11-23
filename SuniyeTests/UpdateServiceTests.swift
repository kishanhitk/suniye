import Foundation
import Sparkle
import XCTest
@testable import Suniye

@MainActor
final class UpdateServiceTests: XCTestCase {
    func testAppBundleEnablesAutomaticDownloadsEveryFiveHours() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, true)
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 18_000)
    }

    func testAppBundleEnablesSuniyeUpdatesByDefault() {
        XCTAssertTrue(Bundle.main.suniyeUpdatesEnabled)
    }

    func testUpdatesEnabledDefaultsTrueWhenKeyMissing() throws {
        XCTAssertTrue(try makeBundle(info: [:]).suniyeUpdatesEnabled)
    }

    func testUpdatesEnabledReadsBoolValues() throws {
        XCTAssertFalse(try makeBundle(info: ["SuniyeUpdatesEnabled": false]).suniyeUpdatesEnabled)
        XCTAssertTrue(try makeBundle(info: ["SuniyeUpdatesEnabled": true]).suniyeUpdatesEnabled)
    }

    func testUpdatesEnabledParsesStringValues() throws {
        for truthy in ["1", "true", " YES "] {
            XCTAssertTrue(try makeBundle(info: ["SuniyeUpdatesEnabled": truthy]).suniyeUpdatesEnabled, truthy)
        }
        for falsy in ["0", "false", "No"] {
            XCTAssertFalse(try makeBundle(info: ["SuniyeUpdatesEnabled": falsy]).suniyeUpdatesEnabled, falsy)
        }
        XCTAssertTrue(try makeBundle(info: ["SuniyeUpdatesEnabled": "maybe"]).suniyeUpdatesEnabled)
    }

    func testUpdatesEnabledIgnoresUnrecognizedType() throws {
        XCTAssertTrue(try makeBundle(info: ["SuniyeUpdatesEnabled": 7]).suniyeUpdatesEnabled)
    }

    func testFactoryPicksControllerByUpdatesEnabled() {
        XCTAssertTrue(AppUpdateControllerFactory.makeDefault(updatesEnabled: false) is DisabledUpdateController)
        XCTAssertTrue(AppUpdateControllerFactory.makeDefault(updatesEnabled: true) is SparkleUpdateController)
    }

    func testDisabledUpdateControllerIsInertButNotifies() {
        let controller = DisabledUpdateController()
        var notifications = 0
        controller.onStateChange = { notifications += 1 }

        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)

        controller.automaticallyChecksForUpdates = true
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
        XCTAssertEqual(notifications, 1)

        controller.updateChannel = .tip
        XCTAssertEqual(controller.updateChannel, .tip)
        XCTAssertEqual(notifications, 2)

        controller.updateChannel = .tip
        XCTAssertEqual(notifications, 2, "no-op channel set must not notify")

        controller.start()
        controller.checkForUpdates()
        XCTAssertEqual(notifications, 4)
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

    func testStagedUpdateInstallsUntilItsUpdateCycleEnds() {
        let controller = SparkleUpdateController()
        let updater = makeUnstartedUpdater()
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
        let updater = makeUnstartedUpdater()

        XCTAssertEqual(controller.allowedChannels(for: updater), [])
        XCTAssertEqual(controller.feedURLString(for: updater), "https://suniye.kishans.in/appcast.xml")

        controller.updateChannel = .tip
        XCTAssertEqual(controller.allowedChannels(for: updater), ["tip"])
        XCTAssertEqual(controller.feedURLString(for: updater), "https://suniye.kishans.in/appcast-tip.xml")
    }

    private func makeUnstartedUpdater() -> SPUUpdater {
        SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        ).updater
    }

    private func makeBundle(info: [String: Any]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuniyeUpdateServiceTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleURL)
        }

        var fullInfo = info
        fullInfo["CFBundleIdentifier"] = "dev.suniye.tests.variant.\(UUID().uuidString)"
        fullInfo["CFBundlePackageType"] = "BNDL"
        let data = try PropertyListSerialization.data(fromPropertyList: fullInfo, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}
