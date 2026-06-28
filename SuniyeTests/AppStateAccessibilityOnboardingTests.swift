import XCTest
@testable import Suniye

@MainActor
final class AppStateAccessibilityOnboardingTests: XCTestCase {
    func testDragHelperEnabledPresentsOverlayAndDoesNotDeepLink() {
        let onboarding = SpyAccessibilityOnboarding()
        var openedURLs: [URL] = []
        let appState = makeTestAppState(
            fileOpener: { url in
                openedURLs.append(url)
                return true
            },
            accessibilityOnboarding: onboarding
        )
        appState.accessibilityDragHelperEnabled = true

        appState.beginAccessibilityOnboarding()

        XCTAssertEqual(onboarding.presentCallCount, 1)
        XCTAssertTrue(openedURLs.isEmpty, "Should not deep-link to System Settings when the overlay is used")
    }

    func testDragHelperDisabledFallsBackToDeepLink() {
        let onboarding = SpyAccessibilityOnboarding()
        var openedURLs: [URL] = []
        let appState = makeTestAppState(
            fileOpener: { url in
                openedURLs.append(url)
                return true
            },
            accessibilityOnboarding: onboarding
        )
        appState.accessibilityDragHelperEnabled = false

        appState.beginAccessibilityOnboarding()

        XCTAssertEqual(onboarding.presentCallCount, 0, "Overlay must not be presented when the kill switch is off")
        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertTrue(
            openedURLs.first?.absoluteString.contains("Privacy_Accessibility") == true,
            "Fallback should open the Accessibility privacy pane, got \(String(describing: openedURLs.first))"
        )
    }

    func testDashboardAttentionFixRoutesThroughOverlay() {
        // The dashboard attention tile is a distinct entry point from the onboarding
        // and settings buttons; it must use the drag overlay, not the native prompt.
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(accessibilityOnboarding: onboarding)
        appState.accessibilityDragHelperEnabled = true

        appState.handleAttentionFixAction(.requestAccessibilityPermission)

        XCTAssertEqual(onboarding.presentCallCount, 1)
    }

    func testGrantCallbackMarksAccessibilityGranted() {
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(accessibilityOnboarding: onboarding)
        appState.accessibilityDragHelperEnabled = true
        appState.hasAccessibilityPermission = false

        appState.beginAccessibilityOnboarding()
        XCTAssertTrue(onboarding.isPresenting)

        onboarding.simulateGrant()

        XCTAssertTrue(appState.hasAccessibilityPermission)
        XCTAssertFalse(onboarding.isPresenting)
    }
}
