import XCTest
import SuniyeAnalytics
@testable import Suniye

@MainActor
final class AppStateAnalyticsTests: XCTestCase {
    func testInitAppliesPersistedEnabledState() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(shareAnalyticsEnabled: false))
        let spy = SpyAnalytics()
        _ = makeTestAppState(generalSettingsStore: store, analytics: spy)
        XCTAssertEqual(spy.enabledStates.last, false)
    }

    func testDefaultEnabledIsTrue() {
        let spy = SpyAnalytics()
        _ = makeTestAppState(analytics: spy)
        XCTAssertEqual(spy.enabledStates.last, true)
    }

    func testTogglePersistsAndUpdatesAnalytics() {
        let store = TestGeneralSettingsStore()
        let spy = SpyAnalytics()
        let appState = makeTestAppState(generalSettingsStore: store, analytics: spy)

        appState.shareAnalyticsEnabled = false

        XCTAssertEqual(store.latest.shareAnalyticsEnabled, false)
        XCTAssertTrue(spy.enabledStates.contains(false))
    }

    func testTogglingBackOnPersists() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(shareAnalyticsEnabled: false))
        let appState = makeTestAppState(generalSettingsStore: store)
        appState.shareAnalyticsEnabled = true
        XCTAssertEqual(store.latest.shareAnalyticsEnabled, true)
    }

    func testRecordSessionEndForwards() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(analytics: spy)
        appState.recordAnalyticsSessionEnd()
        XCTAssertEqual(spy.sessionEndCount, 1)
    }

    func testFlushForwards() async {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(analytics: spy)
        await appState.flushAnalytics()
        XCTAssertGreaterThanOrEqual(spy.flushCount, 1)
    }

    func testOpenPrivacyInfoOpensURL() {
        var opened: URL?
        let appState = makeTestAppState(fileOpener: { url in opened = url; return true })
        appState.openAnalyticsPrivacyInfo()
        XCTAssertTrue(opened?.absoluteString.contains("privacy") ?? false)
    }

    func testDebugBuildDetectionUnderTests() {
        // Running under XCTest must be treated as a debug/excluded build.
        XCTAssertTrue(AppAnalytics.isDebugBuild())
    }

    func testFeatureToggleEmitted() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(analytics: spy)
        appState.autoSubmitEnabled = true
        XCTAssertTrue(spy.trackedEventNames.contains("feature_toggled"))
    }

    func testUpdateChannelChangeEmitted() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(analytics: spy)
        appState.setUpdateChannel(.tip)
        XCTAssertTrue(spy.trackedEventNames.contains("update_action"))
    }

    func testOnboardingCompletionEmittedAtFinish() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .typeAnywhereReached)),
            analytics: spy
        )
        appState.startOnboardingIfNeeded()

        appState.finishOnboarding()

        XCTAssertTrue(spy.trackedEventNames.contains("onboarding_step"))
        XCTAssertTrue(spy.trackedEventNames.contains("onboarding_outcome"))
    }

    func testMagicFormatToggleEmitsFeatureToggled() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(analytics: spy)

        appState.llmEnabled = true

        let toggles = spy.trackedEvents.compactMap { event -> (feature: TrackableFeature, enabled: Bool)? in
            if case let .featureToggled(feature, enabled) = event {
                return (feature, enabled)
            }
            return nil
        }
        XCTAssertTrue(toggles.contains { $0.feature == .magicFormat && $0.enabled })
    }
}
