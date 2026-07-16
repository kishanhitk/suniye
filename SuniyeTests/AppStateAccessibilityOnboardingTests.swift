import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class AppStateAccessibilityOnboardingTests: XCTestCase {
    private func permissionRequests(_ spy: SpyAnalytics) -> [(kind: PermissionKind, surface: PermissionAskSurface, outcome: PermissionAskOutcome)] {
        spy.trackedEvents.compactMap {
            if case let .permissionRequest(kind, surface, outcome) = $0 {
                return (kind, surface, outcome)
            }
            return nil
        }
    }

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

    func testGrantCallbackMarksAccessibilityGrantedAndTracksOutcome() {
        let spy = SpyAnalytics()
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(analytics: spy, accessibilityOnboarding: onboarding)
        appState.accessibilityDragHelperEnabled = true
        appState.hasAccessibilityPermission = false

        appState.beginAccessibilityOnboarding(askSurface: .onboarding)
        XCTAssertTrue(onboarding.isPresenting)

        onboarding.simulateGrant()

        XCTAssertTrue(appState.hasAccessibilityPermission)
        XCTAssertFalse(onboarding.isPresenting)
        let requests = permissionRequests(spy)
        XCTAssertEqual(requests.last?.kind, .accessibility)
        XCTAssertEqual(requests.last?.surface, .onboarding)
        XCTAssertEqual(requests.last?.outcome, .granted)
    }

    func testUserDismissTracksOverlayDismissedAndEnableIsRepressable() {
        let spy = SpyAnalytics()
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(analytics: spy, accessibilityOnboarding: onboarding)
        appState.accessibilityDragHelperEnabled = true

        appState.beginAccessibilityOnboarding()
        onboarding.simulateUserDismiss()

        XCTAssertEqual(permissionRequests(spy).last?.outcome, .overlayDismissed)
        XCTAssertFalse(onboarding.isPresenting)

        // The old latch bug: after backing out, Enable silently no-opped for up
        // to 300s. Re-pressing must re-present immediately.
        appState.beginAccessibilityOnboarding()
        XCTAssertEqual(onboarding.presentCallCount, 2)
        XCTAssertTrue(onboarding.isPresenting)
    }

    func testTimeoutSurfacesVisibleHintAndTracksOutcome() {
        let spy = SpyAnalytics()
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(analytics: spy, accessibilityOnboarding: onboarding)
        appState.accessibilityDragHelperEnabled = true

        appState.beginAccessibilityOnboarding()
        onboarding.simulateTimeout()

        XCTAssertTrue(appState.accessibilityAssistTimedOut, "the silent 300s disappearance must become a visible hint")
        XCTAssertEqual(permissionRequests(spy).last?.outcome, .overlayTimeout)

        // Retrying clears the hint.
        appState.beginAccessibilityOnboarding()
        XCTAssertFalse(appState.accessibilityAssistTimedOut)
    }

    func testStaleTCCGrantSkipsOverlayAndDeepLinks() async {
        // Previously granted (persisted), but AXIsProcessTrusted() now reads
        // false (app update / TCC reset): the drag overlay would mislead — the
        // app is already in the list, just toggled off.
        let onboarding = SpyAccessibilityOnboarding()
        var openedURLs: [URL] = []
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(
                value: GeneralSettings(lastKnownAccessibilityGranted: true)
            ),
            fileOpener: { url in
                openedURLs.append(url)
                return true
            },
            accessibilityOnboarding: onboarding
        )
        appState.accessibilityDragHelperEnabled = true

        appState.beginAccessibilityOnboarding()

        XCTAssertEqual(onboarding.presentCallCount, 0, "stale grants must not present the drag overlay")
        XCTAssertTrue(appState.accessibilityGrantLikelyStale)
        XCTAssertTrue(openedURLs.first?.absoluteString.contains("Privacy_Accessibility") == true)
    }

    func testGrantPersistsLastKnownAccessibilityState() async {
        let store = TestGeneralSettingsStore()
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(generalSettingsStore: store, accessibilityOnboarding: onboarding)
        appState.accessibilityDragHelperEnabled = true

        appState.beginAccessibilityOnboarding()
        onboarding.simulateGrant()

        XCTAssertEqual(store.latest.lastKnownAccessibilityGranted, true)
    }
}
