import SuniyeAnalytics
import XCTest
@testable import Suniye

/// Coverage tests for the 3-screen onboarding state machine (welcome → speak →
/// typeAnywhere), its persisted progress, and the practice-step display state.
@MainActor
final class AppStateCoverageOnboardingTests: XCTestCase {
    /// Fresh install: no model, no flags, nothing granted.
    private func freshOnboardingState(
        spy: SpyAnalytics = SpyAnalytics(),
        store: TestGeneralSettingsStore = TestGeneralSettingsStore(),
        modelManager: StubModelManager = StubModelManager()
    ) -> AppState {
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: store,
            analytics: spy
        )
        appState.phase = .needsModel
        return appState
    }

    private func onboardingStepEvents(_ spy: SpyAnalytics) -> [(step: OnboardingStepName, resumed: Bool?)] {
        spy.trackedEvents.compactMap {
            if case let .onboardingStep(step, _, resumed) = $0 {
                return (step, resumed)
            }
            return nil
        }
    }

    // MARK: - Resume mapping

    func testStartOnboardingSkipsWhenFinished() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished))
        let appState = makeTestAppState(generalSettingsStore: store)

        appState.startOnboardingIfNeeded()

        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
    }

    func testStartOnboardingBeginsAtWelcomeForFreshInstall() {
        let appState = freshOnboardingState()

        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
        XCTAssertFalse(appState.hasSeenOnboardingWelcome)
    }

    func testStartOnboardingResumesPersistedStep() {
        let speak = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached))
        )
        speak.startOnboardingIfNeeded()
        XCTAssertEqual(speak.activeOnboardingStep, .speak)

        let typeAnywhere = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .typeAnywhereReached))
        )
        typeAnywhere.startOnboardingIfNeeded()
        XCTAssertEqual(typeAnywhere.activeOnboardingStep, .typeAnywhere)
    }

    func testResumedStepEventCarriesResumedFlag() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached)),
            analytics: spy
        )

        appState.startOnboardingIfNeeded()

        let events = onboardingStepEvents(spy)
        XCTAssertEqual(events.last?.step, .speak)
        XCTAssertEqual(events.last?.resumed, true)
    }

    func testFreshWelcomeStepEventIsNotResumed() {
        let spy = SpyAnalytics()
        let appState = freshOnboardingState(spy: spy)

        appState.startOnboardingIfNeeded()

        let events = onboardingStepEvents(spy)
        XCTAssertEqual(events.last?.step, .welcome)
        XCTAssertNil(events.last?.resumed)
    }

    func testStepEventsAreDedupedPerRun() {
        let spy = SpyAnalytics()
        let appState = freshOnboardingState(spy: spy)

        appState.startOnboardingIfNeeded()
        appState.activeOnboardingStep = nil
        appState.startOnboardingIfNeeded()

        let welcomeEvents = onboardingStepEvents(spy).filter { $0.step == .welcome }
        XCTAssertEqual(welcomeEvents.count, 1, "re-showing a step within one run must not re-emit onboarding_step")
    }

    // MARK: - Legacy migration through settings load

    func testLegacyInstallWithModelInstalledMigratesToFinished() {
        let store = TestGeneralSettingsStore() // nil flags, nil progress
        let appState = makeTestAppState(generalSettingsStore: store) // StubModelManager has parakeet installed

        appState.startOnboardingIfNeeded()

        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
        XCTAssertEqual(store.latest.onboardingProgress, .finished)
        XCTAssertEqual(store.latest.hasCompletedCoreOnboarding, true)
    }

    func testLegacyMidWizardInstallMigratesToSpeak() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let store = TestGeneralSettingsStore(
            value: GeneralSettings(hasSeenOnboardingWelcome: true, hasCompletedCoreOnboarding: false)
        )
        let appState = makeTestAppState(modelManager: modelManager, generalSettingsStore: store)

        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(store.latest.onboardingProgress, .speakReached)
    }

    func testMigrationDoesNotKeyOnDefaultSensitiveSettings() {
        // The old heuristic auto-completed on autoSubmit/echoCancellation — a
        // future default flip would have skipped onboarding for fresh installs.
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let store = TestGeneralSettingsStore(
            value: GeneralSettings(autoSubmitEnabled: true, echoCancellationEnabled: true)
        )
        let appState = makeTestAppState(modelManager: modelManager, generalSettingsStore: store)

        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
        XCTAssertEqual(store.latest.onboardingProgress, .notStarted)
    }

    func testPersistedProgressWinsOverLegacyBools() {
        // Contradictory legacy Bools must not override the enum.
        let store = TestGeneralSettingsStore(
            value: GeneralSettings(
                hasSeenOnboardingWelcome: false,
                hasCompletedCoreOnboarding: false,
                onboardingProgress: .finished
            )
        )
        let appState = makeTestAppState(generalSettingsStore: store)

        appState.startOnboardingIfNeeded()

        XCTAssertNil(appState.activeOnboardingStep)
    }

    // MARK: - Transitions

    func testGetStartedAdvancesToSpeakPersistsAndStartsDownload() {
        let modelManager = StubModelManager()
        let store = TestGeneralSettingsStore()
        let appState = freshOnboardingState(store: store, modelManager: modelManager)
        appState.startOnboardingIfNeeded()

        appState.beginOnboardingSetup()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(appState.onboardingProgress, .speakReached)
        XCTAssertEqual(store.latest.onboardingProgress, .speakReached)
        XCTAssertEqual(appState.activeASRModelOperationID, .parakeetV3, "Get Started must auto-start the required download")
    }

    func testGetStartedSkipsDownloadWhenModelInstalled() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .notStarted))
        let appState = makeTestAppState(generalSettingsStore: store) // model installed
        appState.phase = .ready
        appState.startOnboardingIfNeeded()

        appState.beginOnboardingSetup()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testGetStartedBlocksOnInsufficientDiskSpace() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let store = TestGeneralSettingsStore()
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: store,
            availableDiskCapacityProvider: { 1_000 } // ~nothing free
        )
        appState.phase = .needsModel
        appState.startOnboardingIfNeeded()

        appState.beginOnboardingSetup()

        XCTAssertEqual(appState.activeOnboardingStep, .welcome, "must stay on welcome with an explanation")
        XCTAssertNotNil(appState.onboardingDiskSpaceMessage)
        XCTAssertEqual(appState.onboardingProgress, .notStarted)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testGetStartedIgnoredOffWelcome() {
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached))
        )
        appState.startOnboardingIfNeeded()

        appState.beginOnboardingSetup()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(appState.onboardingProgress, .speakReached)
    }

    func testAdvanceFromSpeakReachesTypeAnywhere() {
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached))
        )
        appState.startOnboardingIfNeeded()

        appState.advanceOnboardingFromSpeak()

        XCTAssertEqual(appState.activeOnboardingStep, .typeAnywhere)
        XCTAssertEqual(appState.onboardingProgress, .typeAnywhereReached)
    }

    func testAdvanceOnboardingWalksAllSteps() {
        let appState = freshOnboardingState()
        appState.startOnboardingIfNeeded()

        appState.advanceOnboarding() // welcome -> speak
        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        appState.advanceOnboarding() // speak -> typeAnywhere
        XCTAssertEqual(appState.activeOnboardingStep, .typeAnywhere)
        appState.advanceOnboarding() // typeAnywhere -> finished
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.onboardingProgress.isFinished)

        // nil -> restart resolves via startOnboardingIfNeeded (stays finished).
        appState.advanceOnboarding()
        XCTAssertNil(appState.activeOnboardingStep)
    }

    func testFinishOnboardingEmitsCompletionAndOutcome() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .typeAnywhereReached)),
            analytics: spy
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.startOnboardingIfNeeded()

        appState.finishOnboarding()

        XCTAssertTrue(appState.onboardingProgress.isFinished)
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(onboardingStepEvents(spy).contains { $0.step == .completed })

        let outcome = spy.trackedEvents.compactMap { event -> (practiced: Bool, mic: Bool, ax: Bool, model: Bool)? in
            if case let .onboardingOutcome(_, practiced, mic, ax, model) = event {
                return (practiced, mic, ax, model)
            }
            return nil
        }.last
        XCTAssertNotNil(outcome)
        XCTAssertEqual(outcome?.practiced, false)
        XCTAssertEqual(outcome?.mic, true)
        XCTAssertEqual(outcome?.ax, false)
        XCTAssertEqual(outcome?.model, true)
    }

    func testFinishOnboardingIgnoredWhenNotActive() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished)),
            analytics: spy
        )
        appState.startOnboardingIfNeeded()

        appState.finishOnboarding()

        XCTAssertFalse(onboardingStepEvents(spy).contains { $0.step == .completed })
    }

    func testReplayOnboardingRestartsFromWelcome() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished))
        let appState = makeTestAppState(generalSettingsStore: store)
        appState.startOnboardingIfNeeded()
        XCTAssertNil(appState.activeOnboardingStep)

        appState.replayOnboarding()

        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
        XCTAssertEqual(appState.onboardingProgress, .notStarted)
        XCTAssertEqual(store.latest.onboardingProgress, .notStarted)
        XCTAssertEqual(appState.onboardingPracticeAttempts, 0)
        XCTAssertFalse(appState.onboardingPracticeSucceeded)
    }

    // MARK: - Practice display state

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
        appState.activeOnboardingStep = .speak

        appState.phase = .recording
        XCTAssertTrue(appState.isOnboardingPracticeRecording)
        XCTAssertFalse(appState.isOnboardingPracticeProcessing)

        appState.phase = .transcribing
        XCTAssertFalse(appState.isOnboardingPracticeRecording)
        XCTAssertTrue(appState.isOnboardingPracticeProcessing)
    }

    func testLeavingSpeakClearsPracticeResult() {
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached))
        )
        appState.startOnboardingIfNeeded()
        appState.onboardingPracticeResult = OnboardingPracticeResult(message: "done", severity: .success)

        appState.advanceOnboardingFromSpeak()

        XCTAssertNil(appState.onboardingPracticeResult)
    }

    // MARK: - Status item support

    func testSetupMenuItemTitleTracksProgressAndDownloads() {
        let appState = freshOnboardingState()
        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.setupMenuItemTitle, "Finish Setting Up Suniye…")

        appState.phase = .downloadingModel
        appState.downloadProgress = 0.47
        XCTAssertEqual(appState.setupMenuItemTitle, "Downloading speech model — 47%")
    }

    func testSetupMenuItemTitleNilOnceFinished() {
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished))
        )
        XCTAssertNil(appState.setupMenuItemTitle)
    }
}
