import XCTest
@testable import Suniye

final class KeyboardSimulationStrategyTests: XCTestCase {
    private let allowlist: Set<String> = ["com.parsecgaming.parsec"]

    func testAllowlistedAppUsesTypeOutWhenEnabled() {
        let strategy = AppState.keyboardSimulationStrategy(
            enabled: true,
            frontmostBundleID: "com.parsecgaming.parsec",
            allowlist: allowlist
        )
        XCTAssertEqual(strategy, .keyboardTypeOut)
    }

    func testNonAllowlistedAppUsesClipboardPaste() {
        XCTAssertEqual(
            AppState.keyboardSimulationStrategy(enabled: true, frontmostBundleID: "com.apple.mail", allowlist: allowlist),
            .clipboardPaste
        )
    }

    func testDisabledAlwaysUsesClipboardPaste() {
        XCTAssertEqual(
            AppState.keyboardSimulationStrategy(enabled: false, frontmostBundleID: "com.parsecgaming.parsec", allowlist: allowlist),
            .clipboardPaste
        )
    }

    func testNilFrontmostBundleIDUsesClipboardPaste() {
        XCTAssertEqual(
            AppState.keyboardSimulationStrategy(enabled: true, frontmostBundleID: nil, allowlist: allowlist),
            .clipboardPaste
        )
    }

    func testDefaultAllowlistCoversRemoteDesktops() {
        XCTAssertTrue(AppState.keyboardSimulationDefaultBundleIDs.contains("com.parsecgaming.parsec"))
        XCTAssertTrue(AppState.keyboardSimulationDefaultBundleIDs.contains("com.microsoft.rdc.macos"))
    }
}
