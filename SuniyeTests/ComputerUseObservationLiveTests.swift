import Foundation
import XCTest
@testable import Suniye

final class ComputerUseObservationLiveTests: XCTestCase {
    func testCalculatorObservationCapturesAXTextAndScreenshot() async throws {
        let enabled = ProcessInfo.processInfo.environment["SUNIYE_LIVE_COMPUTER_USE"] == "1"
            || UserDefaults.standard.bool(forKey: "SuniyeLiveComputerUseTest")
        guard enabled else {
            throw XCTSkip("Set SUNIYE_LIVE_COMPUTER_USE=1 for the permission-bound live test.")
        }

        let observation = try await ComputerUseObservationService().observe(
            app: "Calculator",
            disableDiff: true
        )

        XCTAssertTrue(observation.state.text.contains("AXWindow"))
        let screenshotURL = try XCTUnwrap(observation.state.screenshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path))
    }
}
