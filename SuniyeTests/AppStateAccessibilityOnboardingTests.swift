import AppKit
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

    func testNeverListedPresentsOverlayAndDoesNotDeepLink() {
        let onboarding = SpyAccessibilityOnboarding()
        var openedURLs: [URL] = []
        let appState = makeTestAppState(
            fileOpener: { url in
                openedURLs.append(url)
                return true
            },
            accessibilityOnboarding: onboarding
        )

        appState.beginAccessibilityOnboarding(askSurface: .onboarding)

        XCTAssertEqual(onboarding.presentCallCount, 1)
        XCTAssertTrue(openedURLs.isEmpty, "Should not deep-link to System Settings when the overlay is used")
        XCTAssertEqual(appState.accessibilityPresentation.primary, .allow)
        XCTAssertNil(appState.accessibilityPresentation.secondary)
    }

    func testSystemPromptShownBeforeSkipsOverlayAndDeepLinks() {
        // The system prompt (hotkey held without access) lists the app in the
        // Accessibility pane switched off; "drag it into the list" would then
        // point at a row that already exists.
        let onboarding = SpyAccessibilityOnboarding()
        var openedURLs: [URL] = []
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(
                value: GeneralSettings(accessibilityPromptShown: true)
            ),
            fileOpener: { url in
                openedURLs.append(url)
                return true
            },
            accessibilityOnboarding: onboarding
        )
        appState.hasAccessibilityPermission = false

        // Derived from the persisted signal: the row already says Open Settings
        // before anything is clicked, so copy and route agree from frame one.
        XCTAssertTrue(appState.accessibilityListedButOff)
        XCTAssertEqual(appState.accessibilityPresentation.primary, .openSettings)

        appState.beginAccessibilityOnboarding(askSurface: .onboarding)

        XCTAssertEqual(onboarding.presentCallCount, 0, "Overlay must not be presented for an already-listed app")
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

        appState.handleAttentionFixAction(.requestAccessibilityPermission)

        XCTAssertEqual(onboarding.presentCallCount, 1)
    }

    func testPermissionActionDispatchesPerKind() {
        let onboarding = SpyAccessibilityOnboarding()
        var openedURLs: [URL] = []
        let appState = makeTestAppState(
            fileOpener: { url in
                openedURLs.append(url)
                return true
            },
            accessibilityOnboarding: onboarding
        )

        appState.performPermissionAction(.allow, for: .accessibility, askSurface: .settings)
        XCTAssertEqual(onboarding.presentCallCount, 1)

        appState.performPermissionAction(.openSettings, for: .accessibility, askSurface: .settings)
        XCTAssertTrue(openedURLs.last?.absoluteString.contains("Privacy_Accessibility") == true)

        appState.performPermissionAction(.openSettings, for: .microphone, askSurface: .settings)
        XCTAssertTrue(openedURLs.last?.absoluteString.contains("Privacy_Microphone") == true)

        appState.dismissAccessibilityAssist()
        XCTAssertFalse(onboarding.isPresenting)
    }

    func testGrantCallbackMarksAccessibilityGrantedAndTracksOutcome() {
        let spy = SpyAnalytics()
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(analytics: spy, accessibilityOnboarding: onboarding)
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

        appState.beginAccessibilityOnboarding(askSurface: .onboarding)
        onboarding.simulateUserDismiss()

        XCTAssertEqual(permissionRequests(spy).last?.outcome, .overlayDismissed)
        XCTAssertFalse(onboarding.isPresenting)
        // Backing out must change the row, not leave the drag copy in place.
        XCTAssertTrue(appState.accessibilityAssistEndedWithoutGrant)
        XCTAssertEqual(appState.accessibilityPresentation.secondary, .openSettings)

        // The old latch bug: after backing out, Enable silently no-opped for up
        // to 300s. Re-pressing must re-present immediately.
        appState.beginAccessibilityOnboarding(askSurface: .onboarding)
        XCTAssertEqual(onboarding.presentCallCount, 2)
        XCTAssertTrue(onboarding.isPresenting)
        XCTAssertFalse(appState.accessibilityAssistEndedWithoutGrant)
    }

    func testTimeoutSurfacesVisibleHintAndTracksOutcome() {
        let spy = SpyAnalytics()
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(analytics: spy, accessibilityOnboarding: onboarding)

        appState.beginAccessibilityOnboarding(askSurface: .onboarding)
        onboarding.simulateTimeout()

        XCTAssertTrue(appState.accessibilityAssistEndedWithoutGrant, "the silent disappearance must become a visible hint")
        XCTAssertEqual(permissionRequests(spy).last?.outcome, .overlayTimeout)

        // Retrying clears the hint.
        appState.beginAccessibilityOnboarding(askSurface: .onboarding)
        XCTAssertFalse(appState.accessibilityAssistEndedWithoutGrant)
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
        appState.hasAccessibilityPermission = false
        XCTAssertTrue(appState.accessibilityListedButOff)

        appState.beginAccessibilityOnboarding(askSurface: .onboarding)

        XCTAssertEqual(onboarding.presentCallCount, 0, "stale grants must not present the drag overlay")
        XCTAssertTrue(openedURLs.first?.absoluteString.contains("Privacy_Accessibility") == true)
    }

    func testGrantPersistsLastKnownAccessibilityState() async {
        let store = TestGeneralSettingsStore()
        let onboarding = SpyAccessibilityOnboarding()
        let appState = makeTestAppState(generalSettingsStore: store, accessibilityOnboarding: onboarding)

        appState.beginAccessibilityOnboarding(askSurface: .onboarding)
        onboarding.simulateGrant()

        XCTAssertEqual(store.latest.lastKnownAccessibilityGranted, true)
        XCTAssertTrue(appState.accessibilityPresentation.isGranted)
    }

    func testPermisoBackDismissesWrapperImmediately() async {
        let notificationCenter = NotificationCenter()
        var dismissCallCount = 0
        var ended: AccessibilityOnboardingEnd?
        let onboarding = PermisoAccessibilityOnboarding(
            isTrusted: { false },
            pollInterval: 60,
            presentOverlay: {},
            dismissOverlay: { dismissCallCount += 1 },
            windowNotificationCenter: notificationCenter,
            overlayWindowMatcher: { _ in true }
        )
        let overlayWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 530, height: 109),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )

        onboarding.present(onGranted: {}, onEnded: { ended = $0 })
        notificationCenter.post(name: NSWindow.willCloseNotification, object: overlayWindow)
        await Task.yield()

        XCTAssertEqual(ended, .dismissed)
        XCTAssertFalse(onboarding.isPresenting)
        XCTAssertEqual(dismissCallCount, 1)
    }
}
