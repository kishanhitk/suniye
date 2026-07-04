import XCTest
@testable import Suniye

/// Coverage tests for the onboarding state machine and its derived
/// practice-step display properties.
@MainActor
final class AppStateCoverageOnboardingTests: XCTestCase {
    private func setupCompleteState(
        localLLMModelManager: LocalLLMModelManagerProtocol = StubLocalLLMModelManager(),
        appleAvailability: AppleFoundationModelsAvailability = .unsupportedSDKOrRuntime
    ) -> AppState {
        let appState = makeTestAppState(
            appleMagicFormatPostProcessor: NoopAppleMagicFormatPostProcessor(availability: appleAvailability),
            localLLMModelManager: localLLMModelManager
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        return appState
    }

    func testStartOnboardingSkipsWhenCompleted() {
        let appState = makeTestAppState()
        appState.hasCompletedCoreOnboarding = true
        appState.activeOnboardingStep = .welcome

        appState.startOnboardingIfNeeded()

        XCTAssertNil(appState.activeOnboardingStep)
    }

    func testStartOnboardingJumpsToMagicFormatWhenSetupIsComplete() {
        let appState = setupCompleteState()

        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .magicFormat)
        XCTAssertTrue(appState.hasSeenOnboardingWelcome)
    }

    func testStartOnboardingShowsWelcomeThenSetup() {
        let appState = makeTestAppState()
        appState.startOnboardingIfNeeded()
        XCTAssertEqual(appState.activeOnboardingStep, .welcome)

        let returning = makeTestAppState()
        returning.hasSeenOnboardingWelcome = true
        returning.startOnboardingIfNeeded()
        XCTAssertEqual(returning.activeOnboardingStep, .setup)
    }

    func testAdvanceOnboardingFromWelcome() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .welcome
        appState.advanceOnboarding()
        XCTAssertEqual(appState.activeOnboardingStep, .setup)
        XCTAssertTrue(appState.hasSeenOnboardingWelcome)

        let complete = setupCompleteState()
        complete.activeOnboardingStep = .welcome
        complete.advanceOnboarding()
        XCTAssertEqual(complete.activeOnboardingStep, .magicFormat)
    }

    func testAdvanceOnboardingFromSetupRequiresCompleteSetup() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .setup

        appState.advanceOnboarding()
        XCTAssertEqual(appState.activeOnboardingStep, .setup)

        let complete = setupCompleteState()
        complete.activeOnboardingStep = .setup
        complete.advanceOnboarding()
        XCTAssertEqual(complete.activeOnboardingStep, .magicFormat)
    }

    func testAdvanceOnboardingFromMagicFormatSkipsToPractice() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .magicFormat

        appState.advanceOnboarding()

        XCTAssertEqual(appState.activeOnboardingStep, .practice)
        XCTAssertFalse(appState.llmEnabled)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
    }

    func testAdvanceOnboardingFromPracticeFinishes() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .practice
        appState.onboardingPracticeResult = OnboardingPracticeResult(message: "done", severity: .success)

        appState.advanceOnboarding()

        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertNil(appState.onboardingPracticeResult)
    }

    func testAdvanceOnboardingFromNilRestartsOnboarding() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = nil

        appState.advanceOnboarding()

        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
    }

    func testGoBackOnboardingOnlyFromSetup() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .setup
        appState.goBackOnboarding()
        XCTAssertEqual(appState.activeOnboardingStep, .welcome)

        appState.activeOnboardingStep = .practice
        appState.goBackOnboarding()
        XCTAssertEqual(appState.activeOnboardingStep, .practice)
    }

    func testConfirmMagicFormatIgnoredOutsideMagicFormatStep() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .setup

        appState.confirmMagicFormatDuringOnboarding(.appleIntelligence)

        XCTAssertFalse(appState.llmEnabled)
        XCTAssertEqual(appState.activeOnboardingStep, .setup)
    }

    func testConfirmMagicFormatLocalModelRequiresSelectableHardware() {
        let manager = StubLocalLLMModelManager()
        manager.isHardwareSupported = false
        let appState = setupCompleteState(localLLMModelManager: manager)
        appState.activeOnboardingStep = .magicFormat

        appState.confirmMagicFormatDuringOnboarding(.localModel)

        XCTAssertFalse(appState.llmEnabled)
        XCTAssertEqual(appState.activeOnboardingStep, .magicFormat)
    }

    func testConfirmMagicFormatLocalModelStartsDownloadAndCompletes() async {
        let manager = StubLocalLLMModelManager()
        let appState = setupCompleteState(localLLMModelManager: manager)
        appState.activeOnboardingStep = .magicFormat

        appState.confirmMagicFormatDuringOnboarding(.localModel)

        XCTAssertEqual(appState.llmProvider, .localGemma)
        XCTAssertTrue(appState.llmEnabled)
        XCTAssertEqual(appState.activeOnboardingStep, .practice)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(manager.downloadCallCount, 1)
    }

    func testConfirmMagicFormatAppleIntelligenceRequiresAvailability() {
        let unavailable = setupCompleteState()
        unavailable.activeOnboardingStep = .magicFormat
        unavailable.confirmMagicFormatDuringOnboarding(.appleIntelligence)
        XCTAssertFalse(unavailable.llmEnabled)
        XCTAssertEqual(unavailable.activeOnboardingStep, .magicFormat)

        let available = setupCompleteState(appleAvailability: .available)
        available.activeOnboardingStep = .magicFormat
        available.confirmMagicFormatDuringOnboarding(.appleIntelligence)
        XCTAssertEqual(available.llmProvider, .appleFoundationModels)
        XCTAssertTrue(available.llmEnabled)
        XCTAssertEqual(available.activeOnboardingStep, .practice)
    }

    func testSkipMagicFormatIgnoredOutsideMagicFormatStep() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .welcome
        appState.llmEnabled = true

        appState.skipMagicFormatDuringOnboarding()

        XCTAssertTrue(appState.llmEnabled)
        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
    }

    func testOnboardingPracticeLevelsFollowIndicatorState() {
        let appState = makeTestAppState()

        let idleLevels = appState.onboardingPracticeLevels
        XCTAssertEqual(idleLevels, Array(repeating: Float(0.08), count: idleLevels.count))

        let levels = Array(repeating: Float(0.6), count: AudioLevelMeter.bandCount)
        appState.floatingIndicatorState = .listening(levels: levels, source: .manual)
        XCTAssertEqual(appState.onboardingPracticeLevels, levels)
    }

    func testOnboardingPracticeActivityFlags() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .practice

        appState.phase = .recording
        XCTAssertTrue(appState.isOnboardingPracticeRecording)
        XCTAssertFalse(appState.isOnboardingPracticeProcessing)

        appState.phase = .transcribing
        XCTAssertFalse(appState.isOnboardingPracticeRecording)
        XCTAssertTrue(appState.isOnboardingPracticeProcessing)
    }

    func testOnboardingLocalModelStatusTextBranches() {
        let appState = makeTestAppState()

        XCTAssertNil(appState.onboardingLocalModelStatusText)

        appState.activeOnboardingStep = .practice
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        appState.localGemmaInstallState = .downloading(LocalLLMDownloadProgress(
            fractionCompleted: 0.5,
            downloadedBytes: 500,
            expectedBytes: 1000
        ))
        XCTAssertNotNil(appState.onboardingLocalModelStatusText)

        appState.localGemmaInstallState = .installed(1000)
        XCTAssertNil(appState.onboardingLocalModelStatusText)

        appState.llmProvider = .openAICompatible
        appState.localGemmaInstallState = .failed("nope")
        XCTAssertNil(appState.onboardingLocalModelStatusText)
    }

    func testCompleteCoreOnboardingResetsPracticeState() {
        let appState = makeTestAppState()
        appState.onboardingPracticeText = "old"
        appState.onboardingPracticeResult = OnboardingPracticeResult(message: "old", severity: .error)

        appState.completeCoreOnboarding()

        XCTAssertTrue(appState.hasSeenOnboardingWelcome)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertNil(appState.onboardingPracticeResult)
        XCTAssertEqual(appState.activeOnboardingStep, .practice)
    }
}
