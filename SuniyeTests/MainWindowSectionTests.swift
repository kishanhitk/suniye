import XCTest
@testable import Suniye

final class MainWindowSectionTests: XCTestCase {
    func testLaunchArgumentsRouteToExpectedSections() {
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye", "--open-dashboard"]), .dashboard)
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye", "--open-history"]), .history)
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye", "--open-model"]), .model)
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye", "--open-style"]), .style)
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye", "--open-general"]), .general)
    }

    func testOpenSettingsCompatibilityAliasRoutesToModel() {
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye", "--open-settings"]), .model)
    }

    func testDefaultSelectionIsDashboard() {
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye"]), .dashboard)
    }

    func testStyleSectionUsesMagicFormatTitle() {
        XCTAssertEqual(MainWindowSection.style.title, "Magic Format")
    }
}
