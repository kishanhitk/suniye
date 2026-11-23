import XCTest
@testable import Suniye

final class AppNameListTests: XCTestCase {
    func testNamesUpToTwoAreListed() {
        XCTAssertEqual(AppNameList.summary([]), "None")
        XCTAssertEqual(AppNameList.summary(["Zoom"]), "Zoom")
        XCTAssertEqual(AppNameList.summary(["Zoom", "Slack"]), "Zoom, Slack")
    }

    /// Teams and Webex each have two bundle IDs, so their names repeat.
    func testRepeatedNamesCountOnce() {
        XCTAssertEqual(AppNameList.summary(["Microsoft Teams", "Microsoft Teams", "Zoom"]), "Microsoft Teams, Zoom")
    }

    func testMoreThanTwoNamesBecomeACount() {
        XCTAssertEqual(AppNameList.summary(["Zoom", "Slack", "Microsoft Teams"]), "3 apps")
        XCTAssertEqual(AppNameList.summary(["Webex", "Webex", "Zoom", "Slack"]), "3 apps")
    }
}
