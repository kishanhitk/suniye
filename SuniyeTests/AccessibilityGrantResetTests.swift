import XCTest
@testable import Suniye

/// Runs stand-in executables, never `/usr/bin/tccutil`: the test host has the
/// real app's bundle id.
final class AccessibilityGrantResetTests: XCTestCase {
    private let succeeds = URL(fileURLWithPath: "/usr/bin/true")
    private let fails = URL(fileURLWithPath: "/usr/bin/false")

    func testExitStatusDecidesTheResult() async {
        let accepted = await AccessibilityGrantReset(bundleIdentifier: "dev.suniye.tests", executableURL: succeeds).run()
        let rejected = await AccessibilityGrantReset(bundleIdentifier: "dev.suniye.tests", executableURL: fails).run()

        XCTAssertTrue(accepted)
        XCTAssertFalse(rejected)
    }

    func testMissingExecutableFailsInsteadOfThrowing() async {
        let missing = URL(fileURLWithPath: "/nonexistent/tccutil")

        let result = await AccessibilityGrantReset(bundleIdentifier: "dev.suniye.tests", executableURL: missing).run()

        XCTAssertFalse(result)
    }

    func testNoBundleIdentifierNeverRuns() async {
        // Without an id, `tccutil reset Accessibility` resets every app.
        let unnamed = await AccessibilityGrantReset(bundleIdentifier: nil, executableURL: succeeds).run()
        let empty = await AccessibilityGrantReset(bundleIdentifier: "", executableURL: succeeds).run()

        XCTAssertFalse(unnamed)
        XCTAssertFalse(empty)
    }
}
