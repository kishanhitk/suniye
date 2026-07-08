import XCTest
@testable import Suniye

final class ScreenReaderTests: XCTestCase {
    func testActionableLabelKeepsActionableEnabledElements() {
        XCTAssertEqual(
            AXTreeReader.actionableLabel(role: "AXButton", title: "Send", description: nil, value: nil, enabled: true),
            "button \"Send\""
        )
        XCTAssertEqual(
            AXTreeReader.actionableLabel(role: "AXTextField", title: nil, description: "Search", value: nil, enabled: true),
            "textfield \"Search\""
        )
    }

    func testActionableLabelDropsNonActionableAndDisabled() {
        XCTAssertNil(AXTreeReader.actionableLabel(role: "AXStaticText", title: "hello", description: nil, value: nil, enabled: true))
        XCTAssertNil(AXTreeReader.actionableLabel(role: "AXButton", title: "Send", description: nil, value: nil, enabled: false))
    }

    func testActionableLabelFallsBackToRoleWhenUnlabeled() {
        XCTAssertEqual(
            AXTreeReader.actionableLabel(role: "AXButton", title: nil, description: nil, value: "", enabled: true),
            "button"
        )
    }

    func testSummaryListsRowsAndFocus() {
        let summary = AXTreeReader.summary(appName: "Mail", focused: "AXTextArea = \"hi\"", rows: ["e0: button \"Send\""])
        XCTAssertTrue(summary.contains("Mail"))
        XCTAssertTrue(summary.contains("e0: button \"Send\""))
        XCTAssertTrue(summary.contains("Focused: AXTextArea"))
    }

    func testSummaryHandlesNoElements() {
        let summary = AXTreeReader.summary(appName: "Finder", focused: nil, rows: [])
        XCTAssertTrue(summary.contains("Finder"))
        XCTAssertTrue(summary.lowercased().contains("no actionable"))
    }
}
