import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class AppStateOnboardingTests: XCTestCase {
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
            if case let .onboardingStep(step, _, resumed, _, _) = $0 {
                return (step, resumed)
            }
            return nil
        }
    }

    func testStartOnboardingSkipsWhenFinished() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished))
        let appState = makeTestAppState(generalSettingsStore: store)

        appState.startOnboardingIfNeeded()

        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
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

    func testWelcomeStartsModelDownloadBeforeLeavingWelcome() async {
        let modelManager = StubModelManager()
        let appState = freshOnboardingState(modelManager: modelManager)

        appState.startOnboardingIfNeeded()
        await waitForOnboardingDownloadToStart(appState)

        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
        XCTAssertEqual(appState.phase, .downloadingModel)
        XCTAssertEqual(appState.activeASRModelOperationID, .parakeetV3)
    }

    func testGetStartedAdvancesToSpeakPersistsAndStartsDownload() async {
        let modelManager = StubModelManager()
        let store = TestGeneralSettingsStore()
        let appState = freshOnboardingState(store: store, modelManager: modelManager)
        appState.startOnboardingIfNeeded()

        await appState.beginOnboardingSetup()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(appState.onboardingProgress, .speakReached)
        XCTAssertEqual(store.latest.onboardingProgress, .speakReached)
        XCTAssertEqual(appState.activeASRModelOperationID, .parakeetV3, "Get Started must auto-start the required download")
    }

    func testGetStartedSkipsDownloadWhenModelInstalled() async {
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .notStarted))
        let appState = makeTestAppState(generalSettingsStore: store) // model installed
        appState.phase = .ready
        appState.startOnboardingIfNeeded()

        await appState.beginOnboardingSetup()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testGetStartedBlocksOnInsufficientDiskSpace() async {
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

        await appState.beginOnboardingSetup()

        XCTAssertEqual(appState.activeOnboardingStep, .welcome, "must stay on welcome with an explanation")
        XCTAssertTrue(appState.onboardingDiskSpaceMessage?.contains("free") == true)
        XCTAssertEqual(appState.onboardingProgress, .notStarted)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testGetStartedIgnoredOffWelcome() async {
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached))
        )
        appState.startOnboardingIfNeeded()

        await appState.beginOnboardingSetup()

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
            if case let .onboardingOutcome(_, practiced, mic, ax, model, _, _) = event {
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

    func testSetupMenuItemTitleTracksProgressAndDownloads() async {
        let appState = freshOnboardingState()
        appState.startOnboardingIfNeeded()
        await waitForOnboardingDownloadToStart(appState)

        XCTAssertEqual(appState.setupMenuItemTitle, "Downloading speech model — 0%")

        appState.phase = .downloadingModel
        appState.downloadProgress = 0.47
        XCTAssertEqual(appState.setupMenuItemTitle, "Downloading speech model — 47%")
    }

    private func waitForOnboardingDownloadToStart(_ appState: AppState) async {
        for _ in 0 ..< 100 {
            if appState.phase == .downloadingModel {
                return
            }
            await Task.yield()
        }
    }

    func testSetupMenuItemTitleNilOnceFinished() {
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished))
        )
        XCTAssertNil(appState.setupMenuItemTitle)
    }

    func testLegacyInstallWithModelInstalledMarksOnboardingComplete() {
        let modelManager = StubModelManager()
        let generalSettingsStore = TestGeneralSettingsStore()

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertTrue(appState.hasSeenOnboardingWelcome)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertEqual(generalSettingsStore.latest.onboardingProgress, .finished)
        // Legacy Bools stay written (derived) for downgrade safety.
        XCTAssertEqual(generalSettingsStore.latest.hasSeenOnboardingWelcome, true)
        XCTAssertEqual(generalSettingsStore.latest.hasCompletedCoreOnboarding, true)
    }

    /// An install from before the onboarding flags counts as a user when the
    /// model it chose is installed, even if that is not the default model.
    func testLegacyInstallWithTheChosenNonDefaultModelInstalledMarksOnboardingComplete() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.moonshineBase]
        let generalSettingsStore = TestGeneralSettingsStore(value: GeneralSettings(selectedASRModelID: .moonshineBase))

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )

        XCTAssertEqual(appState.onboardingProgress, .finished)
        XCTAssertEqual(generalSettingsStore.latest.firstLaunchRecorded, true)
    }

    func testFreshInstallStartsAtWelcome() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore()

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertFalse(appState.hasSeenOnboardingWelcome)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
        XCTAssertEqual(generalSettingsStore.latest.onboardingProgress, .notStarted)
    }

    func testSeenWelcomeResumesSpeak() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false
            )
        )

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(generalSettingsStore.latest.onboardingProgress, .speakReached)
    }

    func testFirstLaunchRecordedFlagPersistsThroughSettings() {
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(firstLaunchRecorded: true)
        )
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        // Any persisting change must round-trip the flag untouched.
        appState.autoSubmitEnabled = true

        XCTAssertEqual(generalSettingsStore.latest.firstLaunchRecorded, true)
    }

    func testLegacyOnboardingStateMarksFirstLaunchAsRecorded() {
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false
            )
        )

        _ = makeTestAppState(generalSettingsStore: generalSettingsStore)

        XCTAssertTrue(generalSettingsStore.latest.firstLaunchRecorded)
    }

    func testLegacyUsageWithoutOnboardingFlagsMarksFirstLaunchAsRecorded() {
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(preferredInputDeviceID: "built-in-microphone")
        )

        _ = makeTestAppState(generalSettingsStore: generalSettingsStore)

        XCTAssertTrue(generalSettingsStore.latest.firstLaunchRecorded)
    }

    func testPracticeModeStoresPreviewWithoutInsertionOrHistory() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello from practice")
        let textInsertionService = SpyTextInsertionService()
        let historyStore = TestHistoryStore()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .speak

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "Hello from practice")
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .success)
        XCTAssertTrue(textInsertionService.insertedTexts.isEmpty)
        XCTAssertEqual(textInsertionService.submitCallCount, 0)
        XCTAssertTrue(appState.recentResults.isEmpty)
        XCTAssertTrue(historyStore.value.isEmpty)
    }

    func testPracticeModeFailureClearsStalePreview() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .failure(FakeError(message: "decoder failed"))
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .speak
        appState.onboardingPracticeText = "Old preview"
        appState.onboardingPracticeResult = OnboardingPracticeResult(
            message: "That's it — this works in any app.",
            severity: .success
        )

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertNil(appState.onboardingPracticeResult)

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .error)
        XCTAssertEqual(appState.onboardingPracticeResult?.message, "decoder failed")
    }

    func testSoundFeedbackEnabledPlaysErrorForEmptyPracticeTranscription() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true
        appState.activeOnboardingStep = .speak

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testRecordingDoesNotStartWhileWelcomeStepIsActive() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .welcome

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 0)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Finish setup first"))
    }

    func testRecordingStartsOnTypeAnywhereStep() async {
        // Real dictation is deliberately allowed on the Accessibility screen
        // (the "try it in Notes" demo depends on it).
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .typeAnywhere

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
    }

    func testModelDownloadSuccessStaysOnSpeakScreen() async {
        // No auto-advance: the screen updates in place when the model turns
        // ready; moving on stays a user action.
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(onboardingProgress: .speakReached)
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()
        appState.hasMicPermission = true

        appState.startModelDownload()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertTrue(appState.asrModelReady)
        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
    }

    func testOnboardingModelDownloadUsesSelectedASRModel() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.activeOnboardingStep = .speak
        appState.hasMicPermission = true

        appState.startModelDownload()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDownloadedModelID, .parakeetV3)
    }
}
