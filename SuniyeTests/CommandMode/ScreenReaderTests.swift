import XCTest
@testable import Suniye

@MainActor
final class ScreenReaderTests: XCTestCase {
    private struct FakeContext: FrontmostContextProviding {
        let appName: String?
        let focusedRoleAndValue: (role: String, value: String)?
    }

    func testSummarizesAppAndFocusedField() async {
        let reader = AXScreenReader(context: FakeContext(appName: "Notes", focusedRoleAndValue: ("AXTextArea", "Hello")))
        let summary = await reader.readScreen()
        XCTAssertTrue(summary.contains("Notes"))
        XCTAssertTrue(summary.contains("AXTextArea"))
    }

    func testHandlesNoFocusGracefully() async {
        let reader = AXScreenReader(context: FakeContext(appName: "Finder", focusedRoleAndValue: nil))
        let summary = await reader.readScreen()
        XCTAssertTrue(summary.contains("Finder"))
        XCTAssertTrue(summary.lowercased().contains("no focused"))
    }
}
