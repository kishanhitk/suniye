import XCTest
@testable import Suniye

@MainActor
final class LocalLLMKeepAliveTests: XCTestCase {
    func testSecondsMapping() {
        XCTAssertEqual(LocalLLMKeepAlive.threeMinutes.seconds, 180)
        XCTAssertEqual(LocalLLMKeepAlive.tenMinutes.seconds, 600)
        XCTAssertEqual(LocalLLMKeepAlive.fifteenMinutes.seconds, 900)
        XCTAssertEqual(LocalLLMKeepAlive.oneHour.seconds, 3600)
    }

    func testAllCasesAreOrderedForThePicker() {
        XCTAssertEqual(
            LocalLLMKeepAlive.allCases,
            [.threeMinutes, .tenMinutes, .fifteenMinutes, .oneHour]
        )
    }

    func testDisplayNames() {
        XCTAssertEqual(LocalLLMKeepAlive.threeMinutes.displayName, "3 minutes")
        XCTAssertEqual(LocalLLMKeepAlive.tenMinutes.displayName, "10 minutes")
        XCTAssertEqual(LocalLLMKeepAlive.fifteenMinutes.displayName, "15 minutes")
        XCTAssertEqual(LocalLLMKeepAlive.oneHour.displayName, "1 hour")
    }

    func testDefaultIsTenMinutes() {
        XCTAssertEqual(LLMSettings().localModelKeepAlive, .tenMinutes)
    }

    func testCoordinatorConfigUsesKeepAliveSetting() {
        var settings = LLMSettings()
        settings.localModelKeepAlive = .fifteenMinutes

        let config = MagicFormatCoordinator.makeLocalGemmaConfig(settings: settings)

        XCTAssertEqual(config.idleTimeoutSeconds, 900)
    }

    func testCoordinatorConfigDefaultsToTenMinuteKeepAlive() {
        let config = MagicFormatCoordinator.makeLocalGemmaConfig(settings: LLMSettings())

        XCTAssertEqual(config.idleTimeoutSeconds, 600)
    }
}
