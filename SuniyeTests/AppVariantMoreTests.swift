import XCTest
@testable import Suniye

final class AppVariantMoreTests: XCTestCase {
    private func makeBundle(info: [String: Any]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuniyeAppVariantMoreTests-\(UUID().uuidString).bundle")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleURL)
        }

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        var fullInfo = info
        if fullInfo["CFBundleIdentifier"] == nil {
            fullInfo["CFBundleIdentifier"] = "dev.suniye.tests.variant.\(UUID().uuidString)"
        }
        fullInfo["CFBundlePackageType"] = "BNDL"
        let data = try PropertyListSerialization.data(fromPropertyList: fullInfo, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    // MARK: - AppIdentity

    func testAppIdentityFallsBackToBundleNameThenDefault() throws {
        let named = AppIdentity.fromBundle(try makeBundle(info: ["CFBundleName": "Named App"]))
        XCTAssertEqual(named.displayName, "Named App")
        XCTAssertFalse(named.isPreview)

        let unnamed = AppIdentity.fromBundle(try makeBundle(info: [:]))
        XCTAssertEqual(unnamed.displayName, AppIdentity.fallbackDisplayName)

        let blank = AppIdentity.fromBundle(try makeBundle(info: ["CFBundleDisplayName": "   "]))
        XCTAssertEqual(blank.displayName, AppIdentity.fallbackDisplayName)
    }

    func testAppIdentityDetectsPreviewBySuffix() throws {
        let suffixed = AppIdentity.fromBundle(
            try makeBundle(info: ["CFBundleIdentifier": "dev.example.other.preview"])
        )
        XCTAssertTrue(suffixed.isPreview)

        let stable = AppIdentity.fromBundle(
            try makeBundle(info: ["CFBundleIdentifier": "dev.suniye.app"])
        )
        XCTAssertFalse(stable.isPreview)
    }

    func testAppIdentityCurrentReflectsTestHostBundle() {
        XCTAssertFalse(AppIdentity.current.displayName.isEmpty)
    }

    // MARK: - DisabledUpdateController

    @MainActor
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

    // MARK: - AppUpdateControllerFactory

    @MainActor
    func testFactoryPicksControllerByUpdatesEnabled() {
        XCTAssertTrue(AppUpdateControllerFactory.makeDefault(updatesEnabled: false) is DisabledUpdateController)
        XCTAssertTrue(AppUpdateControllerFactory.makeDefault(updatesEnabled: true) is SparkleUpdateController)
    }

    // MARK: - Bundle.suniyeUpdatesEnabled

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
}
