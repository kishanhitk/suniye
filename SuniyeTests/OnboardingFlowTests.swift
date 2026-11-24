import XCTest
@testable import Suniye

/// The last onboarding steps: practice, a first dictation into another app, then Finish.
@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testPracticeStaysInOnboardingAndTheFirstRealDictationLeadsToFinish() async throws {
        let app = try FlowApp(self, general: GeneralSettings(onboardingProgress: .speakReached))
        await app.launch()
        XCTAssertEqual(app.appState.activeOnboardingStep, .speak)

        await app.dictate(saying: "On my way.")

        XCTAssertEqual(app.appState.onboardingPracticeText, "On my way.")
        XCTAssertEqual(app.focusedApp.text, "", "a practice dictation is shown in onboarding, not pasted")
        XCTAssertTrue(app.appState.recentResults.isEmpty)

        app.appState.advanceOnboardingFromSpeak()
        XCTAssertEqual(app.appState.activeOnboardingStep, .typeAnywhere)
        app.frontmostBundleID = "com.apple.Notes"
        await app.dictate(saying: "Buy milk.")
        await waitUntil { app.appState.activeOnboardingStep == .more }

        XCTAssertEqual(app.focusedApp.text, "Buy milk.")
        app.appState.finishOnboarding()
        XCTAssertNil(app.appState.activeOnboardingStep)
        XCTAssertEqual(GeneralSettingsStore(userDefaults: app.defaults).load().onboardingProgress, .finished)
    }
}
