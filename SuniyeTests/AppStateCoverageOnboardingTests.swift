import SuniyeAnalytics
import XCTest
@testable import Suniye

/// Coverage tests for the 2-screen onboarding state machine (speak →
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
        XCTAssertTrue(appState.onboardingProgress.isFinished)
    }

    func testFreshInstallShowsDictateScreenFromConstruction() {
        // The step is derived at hydration, so the first frame is onboarding —
        // not a dashboard that gets swapped out once bootstrap finishes.
        let appState = freshOnboardingState()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(appState.onboardingProgress, .notStarted)
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

    func testFreshFirstStepEventIsNotResumed() {
        let spy = SpyAnalytics()
        let appState = freshOnboardingState(spy: spy)

        appState.startOnboardingIfNeeded()

        let events = onboardingStepEvents(spy)
        XCTAssertEqual(events.last?.step, .speak)
        XCTAssertNil(events.last?.resumed)
    }

    func testStepEventsAreDedupedPerRun() {
        let spy = SpyAnalytics()
        let appState = freshOnboardingState(spy: spy)

        appState.startOnboardingIfNeeded()
        appState.activeOnboardingStep = nil
        appState.startOnboardingIfNeeded()

        let speakEvents = onboardingStepEvents(spy).filter { $0.step == .speak }
        XCTAssertEqual(speakEvents.count, 1, "re-showing a step within one run must not re-emit onboarding_step")
    }

    // MARK: - Legacy migration through settings load

    func testLegacyInstallWithModelInstalledMigratesToFinished() {
        let store = TestGeneralSettingsStore() // nil flags, nil progress
        let appState = makeTestAppState(generalSettingsStore: store) // StubModelManager has parakeet installed

        appState.startOnboardingIfNeeded()

        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.onboardingProgress.isFinished)
        XCTAssertEqual(store.latest.onboardingProgress, .finished)
        XCTAssertNil(store.latest.hasCompletedCoreOnboarding, "legacy Bools are read for migration, never written again")
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

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
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

    func testStartOnboardingStartsModelDownloadOnFirstScreen() async {
        let modelManager = StubModelManager()
        let appState = freshOnboardingState(modelManager: modelManager)

        appState.startOnboardingIfNeeded()
        await waitForOnboardingDownloadToStart(appState)

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(appState.phase, .downloadingModel)
        XCTAssertEqual(appState.activeASRModelOperationID, .parakeetV3)
    }

    func testResumedStepRestartsModelDownload() async {
        // Quit mid-download, relaunch: the Dictate screen must not sit on a
        // stalled model with only a link to click.
        let modelManager = StubModelManager()
        let appState = freshOnboardingState(
            store: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .typeAnywhereReached)),
            modelManager: modelManager
        )

        appState.startOnboardingIfNeeded()
        await waitForOnboardingDownloadToStart(appState)

        XCTAssertEqual(appState.activeOnboardingStep, .typeAnywhere)
        XCTAssertEqual(appState.activeASRModelOperationID, .parakeetV3)
    }

    func testStartOnboardingSkipsDownloadWhenModelInstalled() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .notStarted))
        let appState = makeTestAppState(generalSettingsStore: store) // model installed
        appState.phase = .ready

        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testInsufficientDiskSpaceSurfacesMessageInsteadOfDownloading() async {
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
        for _ in 0 ..< 100 where appState.onboardingDiskSpaceMessage == nil {
            await Task.yield()
        }

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertNotNil(appState.onboardingDiskSpaceMessage)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testRetryAfterDiskRefusalClearsMessageAndDownloads() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        var freeBytes: Int64 = 1_000
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: TestGeneralSettingsStore(),
            availableDiskCapacityProvider: { freeBytes }
        )
        appState.phase = .needsModel
        appState.startOnboardingIfNeeded()
        for _ in 0 ..< 100 where appState.onboardingDiskSpaceMessage == nil {
            await Task.yield()
        }
        XCTAssertNotNil(appState.onboardingDiskSpaceMessage)

        freeBytes = .max
        appState.retryOnboardingModelDownload()
        await waitForOnboardingDownloadToStart(appState)

        XCTAssertNil(appState.onboardingDiskSpaceMessage)
        XCTAssertEqual(appState.activeASRModelOperationID, .parakeetV3)
    }

    func testRetryAfterFailedDownloadRestartsImmediately() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager, generalSettingsStore: TestGeneralSettingsStore())
        appState.phase = .error

        appState.retryOnboardingModelDownload()

        XCTAssertEqual(appState.activeASRModelOperationID, .parakeetV3)
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

    func testTransitionsWalkBothScreens() {
        let appState = freshOnboardingState()
        appState.startOnboardingIfNeeded()

        appState.advanceOnboardingFromSpeak()
        XCTAssertEqual(appState.activeOnboardingStep, .typeAnywhere)
        appState.finishOnboarding()
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.onboardingProgress.isFinished)

        // Restarting once finished stays finished.
        appState.startOnboardingIfNeeded()
        XCTAssertNil(appState.activeOnboardingStep)
    }

    func testLaterDefersAccessibilityAndDashboardExplainsClipboardMode() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .typeAnywhereReached))
        let appState = makeTestAppState(generalSettingsStore: store)
        appState.hasAccessibilityPermission = false

        appState.finishOnboarding(deferringAccessibility: true)

        XCTAssertTrue(appState.onboardingProgress.isFinished)
        XCTAssertEqual(store.latest.accessibilityDeferred, true)
        let item = appState.attentionItems.first { $0.id == "accessibility-deferred" }
        XCTAssertEqual(item?.severity, .info)
        XCTAssertEqual(item?.fixAction, .requestAccessibilityPermission)
        XCTAssertEqual(item?.fixTitle, "Allow Access")
        XCTAssertNil(appState.attentionItems.first { $0.id == "accessibility-permission-missing" })
    }

    func testFinishWithAccessibilityGrantedDoesNotRecordDeferral() {
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .typeAnywhereReached))
        let appState = makeTestAppState(generalSettingsStore: store)
        appState.hasAccessibilityPermission = true

        appState.finishOnboarding(deferringAccessibility: true)

        XCTAssertEqual(store.latest.accessibilityDeferred, false)
    }

    func testGrantClearsDeferralAndTheClipboardModeTile() async {
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(
                value: GeneralSettings(onboardingProgress: .finished, accessibilityDeferred: true)
            ),
            accessibilityTrustProvider: { true }
        )
        appState.hasAccessibilityPermission = false
        XCTAssertNotNil(appState.attentionItems.first { $0.id == "accessibility-deferred" })

        await appState.refreshPermissions()

        XCTAssertTrue(appState.hasAccessibilityPermission)
        XCTAssertNil(appState.attentionItems.first { $0.id == "accessibility-deferred" })
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

    // MARK: - Practice display state

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
}
