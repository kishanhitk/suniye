import Foundation
import XCTest
@testable import Suniye

@MainActor
final class UpdateConfigurationTests: XCTestCase {
    private static let sparkleDefaultsKeys = [
        "SUEnableAutomaticChecks",
        "SUAutomaticallyUpdate",
        "SUScheduledCheckInterval",
    ]

    func testAppBundleEnablesAutomaticDownloadsEveryFiveHours() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, true)
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 18_000)
    }

    func testSparkleUpdaterResolvesAutomaticDownloadDefaultsFromBundle() {
        // Sparkle mirrors these keys into UserDefaults once a user expresses a
        // preference; clear them so the updater falls back to the bundle plist.
        let defaults = UserDefaults.standard
        let savedValues = Self.sparkleDefaultsKeys.map { ($0, defaults.object(forKey: $0)) }
        Self.sparkleDefaultsKeys.forEach { defaults.removeObject(forKey: $0) }
        addTeardownBlock {
            for (key, value) in savedValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let controller = SparkleUpdateController()

        XCTAssertTrue(controller.automaticallyDownloadsUpdates)
        XCTAssertEqual(controller.updateCheckInterval, 18_000)
    }
}
