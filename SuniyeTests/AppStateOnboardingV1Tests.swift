import AVFoundation
import XCTest
import SuniyeAnalytics
@testable import Suniye

/// KIS-247: Apple Speech as the fresh-install default, the fixed bootstrap
/// restore of a system-managed model, the release-during-prompt cancel, the
/// closing "more" step, and the analytics each of those emits.
@MainActor
final class AppStateOnboardingV1Tests: XCTestCase {
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func drain() async {
        for _ in 0 ..< 8 { await Task.yield() }
    }

    private func systemDefaultEvents(_ spy: SpyAnalytics) -> [(outcome: SystemDefaultModelOutcome, reason: SystemDefaultModelReason?, model: SafeLabel?, durationMs: Int)] {
        spy.trackedEvents.compactMap {
            if case let .systemDefaultModel(outcome, reason, model, durationMs) = $0 {
                return (outcome, reason, model, durationMs)
            }
            return nil
        }
    }

    private func stepEvents(_ spy: SpyAnalytics) -> [(step: OnboardingStepName, elapsedMs: Int?, advancedBy: OnboardingAdvance?)] {
        spy.trackedEvents.compactMap {
            if case let .onboardingStep(step, _, _, elapsedMs, advancedBy) = $0 {
                return (step, elapsedMs, advancedBy)
            }
            return nil
        }
    }

    private func outcomeEvents(_ spy: SpyAnalytics) -> [(endedBy: OnboardingEnd?, practiceEdited: Bool?)] {
        spy.trackedEvents.compactMap {
            if case let .onboardingOutcome(_, _, _, _, _, endedBy, practiceEdited) = $0 {
                return (endedBy, practiceEdited)
            }
            return nil
        }
    }

    private func blockedReasons(_ spy: SpyAnalytics) -> [DictationBlockedReason] {
        spy.trackedEvents.compactMap {
            if case let .dictationBlocked(reason) = $0 {
                return reason
            }
            return nil
        }
    }

    private func micRequestSurfaces(_ spy: SpyAnalytics) -> [PermissionAskSurface] {
        spy.trackedEvents.compactMap {
            if case let .permissionRequest(.microphone, surface, _) = $0 {
                return surface
            }
            return nil
        }
    }

    /// The stub mirrors the real manager: a built-in model "is installed" when the
    /// OS can run it, while installedModels() still lists only downloaded files.
    private func makeBuiltInAvailable(_ modelManager: StubModelManager) {
        modelManager.installedModelIDs.insert(.appleSpeech)
        modelManager.recognizerConfigs[.appleSpeech] = RecognizerConfig(
            modelID: .appleSpeech,
            family: .appleSpeech,
            tokensPath: "",
            numThreads: 4
        )
    }

    /// A fresh install: no downloaded models, onboarding not started.
    private func freshInstall(
        spy: SpyAnalytics,
        modelManager: StubModelManager,
        transcription: StubTranscriptionService = StubTranscriptionService(),
        progress: OnboardingProgress = .notStarted,
        nowProvider: @escaping () -> Date = Date.init
    ) -> AppState {
        modelManager.installedModelIDs = []
        return makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: progress)),
            analytics: spy,
            nowProvider: nowProvider
        )
    }

    // MARK: - Built-in model as the fresh-install default

    func testFreshInstallAdoptsReadySystemModel() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.systemDefaultCheck = .ready(.appleSpeech)
        let transcription = StubTranscriptionService()
        let appState = freshInstall(spy: spy, modelManager: modelManager, transcription: transcription)
        makeBuiltInAvailable(modelManager)

        await appState.bootstrap()

        XCTAssertEqual(appState.selectedASRModelID, .appleSpeech)
        XCTAssertEqual(appState.loadedASRModelID, .appleSpeech)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(transcription.transcribeCallCount, 1, "one silent decode proves the engine runs")
        XCTAssertNil(appState.activeASRModelOperationID)
        XCTAssertNil(modelManager.lastDownloadedModelID, "an adopted built-in model needs no download")
        let events = systemDefaultEvents(spy)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.outcome, .adopted)
        XCTAssertNil(events.first?.reason)
        XCTAssertEqual(events.first?.model, SafeLabel(ASRModelID.appleSpeech.rawValue))
        XCTAssertGreaterThanOrEqual(events.first?.durationMs ?? -1, 0)
    }

    func testUnavailableSystemModelFallsBackToDownload() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.systemDefaultCheck = .unavailable(reason: .unsupportedLanguage, detail: "ga-IE")
        let appState = freshInstall(spy: spy, modelManager: modelManager)

        await appState.bootstrap()
        await waitUntil { modelManager.lastDownloadedModelID != nil }

        XCTAssertEqual(modelManager.systemDefaultCheckCallCount, 1)
        XCTAssertEqual(modelManager.lastDownloadedModelID, .parakeetV3, "the downloaded default takes over")
        let events = systemDefaultEvents(spy)
        XCTAssertEqual(events.map(\.outcome), [.unavailable])
        XCTAssertEqual(events.first?.reason, .unsupportedLanguage)
        XCTAssertNil(events.first?.model)
    }

    func testUnavailableSystemModelLeavesNeedsModelWhenNothingDownloads() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.systemDefaultCheck = .unavailable(reason: .osTooOld, detail: "macOS 15")
        // Disk preflight refuses, so nothing starts and the phase is observable.
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .notStarted)),
            analytics: spy,
            availableDiskCapacityProvider: { 1 }
        )
        modelManager.installedModelIDs = []

        await appState.bootstrap()
        await drain()

        XCTAssertEqual(appState.phase, .needsModel)
        XCTAssertEqual(appState.statusText, "Model required")
        XCTAssertEqual(systemDefaultEvents(spy).first?.reason, .osTooOld)
    }

    func testSystemModelLoadFailureReportsLoadFailed() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.systemDefaultCheck = .ready(.appleSpeech)
        let transcription = StubTranscriptionService()
        transcription.loadModelErrorsByModelID[.appleSpeech] = FakeError(message: "no engine")
        let appState = freshInstall(spy: spy, modelManager: modelManager, transcription: transcription)
        makeBuiltInAvailable(modelManager)

        await appState.bootstrap()

        XCTAssertNotEqual(appState.selectedASRModelID, .appleSpeech)
        XCTAssertNotEqual(appState.loadedASRModelID, .appleSpeech)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
        let events = systemDefaultEvents(spy)
        XCTAssertEqual(events.first?.outcome, .failed)
        XCTAssertEqual(events.first?.reason, .loadFailed)
        XCTAssertEqual(events.first?.model, SafeLabel(ASRModelID.appleSpeech.rawValue))
    }

    func testSystemModelDecodeFailureUnloadsAndReportsDecodeFailed() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.systemDefaultCheck = .ready(.appleSpeech)
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .failure(FakeError(message: "analyzer refused"))
        let appState = freshInstall(spy: spy, modelManager: modelManager, transcription: transcription)
        makeBuiltInAvailable(modelManager)

        await appState.bootstrap()

        XCTAssertNotEqual(appState.selectedASRModelID, .appleSpeech)
        XCTAssertEqual(transcription.unloadCallCount, 1)
        XCTAssertNotEqual(appState.loadedASRModelID, .appleSpeech, "a failed engine must not stay loaded")
        let events = systemDefaultEvents(spy)
        XCTAssertEqual(events.first?.outcome, .failed)
        XCTAssertEqual(events.first?.reason, .decodeFailed)
    }

    func testFinishedOnboardingNeverRunsTheSystemCheck() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.systemDefaultCheck = .ready(.appleSpeech)
        let appState = freshInstall(spy: spy, modelManager: modelManager, progress: .finished)

        await appState.bootstrap()

        XCTAssertEqual(modelManager.systemDefaultCheckCallCount, 0)
        XCTAssertEqual(appState.phase, .needsModel)
        XCTAssertTrue(systemDefaultEvents(spy).isEmpty)
    }

    // MARK: - Bootstrap restore of a chosen system-managed model

    func testBootstrapRestoresSelectedSystemManagedModel() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .appleSpeech]
        let transcription = StubTranscriptionService()
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(
                onboardingProgress: .finished,
                selectedASRModelID: .appleSpeech
            ))
        )

        await appState.bootstrap()

        XCTAssertEqual(transcription.loadCallCount, 1, "the chosen model loads first, so nothing else is tried")
        XCTAssertEqual(appState.loadedASRModelID, .appleSpeech)
        XCTAssertEqual(appState.selectedASRModelID, .appleSpeech, "a launch must not silently switch to a downloaded model")
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(modelManager.systemDefaultCheckCallCount, 0)
    }

    // MARK: - Presenting vs. starting onboarding

    func testPresentOnboardingShowsStepWithoutStartingDownload() {
        let modelManager = StubModelManager()
        let appState = freshInstall(spy: SpyAnalytics(), modelManager: modelManager)
        appState.phase = .needsModel

        appState.presentOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
        XCTAssertNil(appState.activeASRModelOperationID)
        XCTAssertNotEqual(appState.phase, .downloadingModel)
        XCTAssertNil(modelManager.lastDownloadedModelID)
    }

    func testPresentOnboardingIsNoOpWhenAlreadyShowing() {
        let spy = SpyAnalytics()
        let appState = freshInstall(spy: spy, modelManager: StubModelManager(), progress: .speakReached)

        appState.presentOnboardingIfNeeded()
        appState.presentOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(stepEvents(spy).count, 1)
    }

    func testPresentOnboardingClearsStepWhenFinished() {
        let appState = freshInstall(spy: SpyAnalytics(), modelManager: StubModelManager(), progress: .finished)
        appState.activeOnboardingStep = .speak

        appState.presentOnboardingIfNeeded()

        XCTAssertNil(appState.activeOnboardingStep)
    }

    func testResumedSpeakStepRestartsTheDownload() async {
        let modelManager = StubModelManager()
        let appState = freshInstall(spy: SpyAnalytics(), modelManager: modelManager, progress: .speakReached)
        appState.phase = .needsModel

        appState.startOnboardingIfNeeded()
        await waitUntil { modelManager.lastDownloadedModelID != nil }

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(modelManager.lastDownloadedModelID, .parakeetV3)
    }

    // MARK: - Microphone asked on the Welcome click

    func testBeginOnboardingSetupAsksForTheMicrophone() async {
        let spy = SpyAnalytics()
        var requested = 0
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3]
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .notStarted)),
            analytics: spy,
            micAccessRequester: {
                requested += 1
                return true
            }
        )
        appState.startOnboardingIfNeeded()

        await appState.beginOnboardingSetup()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertEqual(requested, 1)
        XCTAssertTrue(appState.hasMicPermission)
        XCTAssertEqual(micRequestSurfaces(spy), [.onboarding])
    }

    func testBeginOnboardingSetupSkipsMicrophoneWhenAlreadyDecided() async {
        for status in [AVAuthorizationStatus.authorized, .denied] {
            let spy = SpyAnalytics()
            var requested = 0
            let modelManager = StubModelManager()
            modelManager.installedModelIDs = [.parakeetV3]
            let appState = makeTestAppState(
                modelManager: modelManager,
                generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .notStarted)),
                analytics: spy,
                micAuthorizationStatusProvider: { status },
                micAccessRequester: {
                    requested += 1
                    return true
                }
            )
            await appState.refreshPermissions()
            appState.startOnboardingIfNeeded()

            await appState.beginOnboardingSetup()

            XCTAssertEqual(appState.activeOnboardingStep, .speak)
            XCTAssertEqual(requested, 0, "no prompt when the answer is already \(status.rawValue)")
            XCTAssertTrue(micRequestSurfaces(spy).isEmpty)
        }
    }

    // MARK: - Key released while a permission prompt is open

    private func hotkeyDrivenState(
        spy: SpyAnalytics,
        hotkey: StubHotkeyService,
        audio: StubAudioCaptureService,
        gate: AsyncGate
    ) async -> AppState {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3]
        let appState = makeTestAppState(
            modelManager: modelManager,
            audioCaptureService: audio,
            hotkeyService: hotkey,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished)),
            analytics: spy,
            micAccessRequester: {
                await gate.wait()
                return true
            },
            startServices: true
        )
        await waitUntil { appState.phase == .ready }
        appState.hasMicPermission = false
        appState.hasAccessibilityPermission = true
        return appState
    }

    func testReleaseDuringMicPromptCancelsTheStart() async {
        let spy = SpyAnalytics()
        let hotkey = StubHotkeyService()
        let audio = StubAudioCaptureService()
        let gate = AsyncGate()
        let appState = await hotkeyDrivenState(spy: spy, hotkey: hotkey, audio: audio, gate: gate)
        XCTAssertEqual(appState.phase, .ready)

        hotkey.onHotkeyDown?()
        await drain()
        hotkey.onHotkeyUp?()
        await drain()
        gate.open()
        await waitUntil { blockedReasons(spy).contains(.releasedDuringPrompt) }

        XCTAssertEqual(audio.startCaptureCallCount, 0, "nothing may record after the key is already up")
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertTrue(appState.hasMicPermission)
        XCTAssertEqual(blockedReasons(spy), [.releasedDuringPrompt])
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Hold again to dictate"))
    }

    func testHoldingThroughMicPromptStillRecords() async {
        let spy = SpyAnalytics()
        let hotkey = StubHotkeyService()
        let audio = StubAudioCaptureService()
        let gate = AsyncGate()
        let appState = await hotkeyDrivenState(spy: spy, hotkey: hotkey, audio: audio, gate: gate)

        hotkey.onHotkeyDown?()
        await drain()
        gate.open()
        await waitUntil { appState.phase == .recording }

        XCTAssertEqual(appState.phase, .recording)
        XCTAssertEqual(audio.startCaptureCallCount, 1)
        XCTAssertFalse(blockedReasons(spy).contains(.releasedDuringPrompt))
    }

    // MARK: - Closing "more" step

    private func typeAnywhereState(
        spy: SpyAnalytics,
        audio: StubAudioCaptureService = StubAudioCaptureService(),
        transcription: StubTranscriptionService = StubTranscriptionService(),
        frontmostApp: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) -> AppState {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription,
            audioCaptureService: audio,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .typeAnywhereReached)),
            analytics: spy,
            nowProvider: nowProvider,
            frontmostAppBundleIDProvider: { frontmostApp }
        )
        appState.startOnboardingIfNeeded()
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        return appState
    }

    func testContinueFromTypeAnywhereShowsMoreWithButtonAndElapsed() {
        let spy = SpyAnalytics()
        var now = Date(timeIntervalSince1970: 1_000)
        let appState = typeAnywhereState(spy: spy, nowProvider: { now })
        now = now.addingTimeInterval(7)

        appState.advanceOnboardingFromTypeAnywhere()

        XCTAssertEqual(appState.activeOnboardingStep, .more)
        XCTAssertEqual(appState.onboardingProgress, .typeAnywhereReached, "the closing step is not persisted on its own")
        let more = stepEvents(spy).first { $0.step == .more }
        XCTAssertEqual(more?.advancedBy, .button)
        XCTAssertEqual(more?.elapsedMs, 7_000)
    }

    func testAdvanceFromTypeAnywhereIgnoredOnOtherSteps() {
        let appState = freshInstall(spy: SpyAnalytics(), modelManager: StubModelManager(), progress: .speakReached)
        appState.startOnboardingIfNeeded()

        appState.advanceOnboardingFromTypeAnywhere()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
    }

    func testAdvanceOnboardingWalksIntoMoreThenFinishes() async {
        let spy = SpyAnalytics()
        let appState = typeAnywhereState(spy: spy)

        await appState.advanceOnboarding()
        XCTAssertEqual(appState.activeOnboardingStep, .more)
        await appState.advanceOnboarding()

        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.onboardingProgress.isFinished)
    }

    private func dictate(_ appState: AppState, audio: StubAudioCaptureService, transcription: StubTranscriptionService) async {
        audio.stopCaptureResult = makeValidCapturedAudio()
        transcription.transcribeResult = .success("on my way")
        let started = expectation(description: "started")
        let transcribed = expectation(description: "transcribed")
        audio.onStartCapture = { _ in started.fulfill() }
        transcription.onTranscribe = { transcribed.fulfill() }
        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await fulfillment(of: [transcribed], timeout: 1)
        await drain()
    }

    func testFirstInsertionIntoAnotherAppAdvancesToMore() async {
        let spy = SpyAnalytics()
        let audio = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        let appState = typeAnywhereState(spy: spy, audio: audio, transcription: transcription, frontmostApp: "com.apple.Notes")

        await dictate(appState, audio: audio, transcription: transcription)
        await waitUntil { appState.activeOnboardingStep == .more }

        XCTAssertEqual(appState.activeOnboardingStep, .more)
        XCTAssertEqual(stepEvents(spy).first { $0.step == .more }?.advancedBy, .insertion)
    }

    func testInsertionIntoSuniyeItselfDoesNotAdvance() async {
        let spy = SpyAnalytics()
        let audio = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        let appState = typeAnywhereState(
            spy: spy,
            audio: audio,
            transcription: transcription,
            frontmostApp: Bundle.main.bundleIdentifier
        )

        await dictate(appState, audio: audio, transcription: transcription)

        XCTAssertEqual(appState.activeOnboardingStep, .typeAnywhere)
    }

    // MARK: - How onboarding ends

    private func practiceThenFinish(editTo editedText: String?, endedBy: OnboardingEnd) async -> SpyAnalytics {
        let spy = SpyAnalytics()
        let audio = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audio,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached)),
            analytics: spy
        )
        appState.startOnboardingIfNeeded()
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        await dictate(appState, audio: audio, transcription: transcription)
        await waitUntil { appState.onboardingPracticeSucceeded }
        XCTAssertEqual(appState.onboardingPracticeText, "on my way")
        if let editedText {
            appState.onboardingPracticeText = editedText
        }
        appState.advanceOnboardingFromSpeak()
        appState.finishOnboarding(endedBy: endedBy)
        return spy
    }

    func testFinishReportsEditedPractice() async {
        let spy = await practiceThenFinish(editTo: "On my way!", endedBy: .finishButton)

        XCTAssertEqual(outcomeEvents(spy).first?.endedBy, .finishButton)
        XCTAssertEqual(outcomeEvents(spy).first?.practiceEdited, true)
    }

    func testWindowCloseReportsUneditedPractice() async {
        let spy = await practiceThenFinish(editTo: nil, endedBy: .windowClosed)

        XCTAssertEqual(outcomeEvents(spy).first?.endedBy, .windowClosed)
        XCTAssertEqual(outcomeEvents(spy).first?.practiceEdited, false)
    }

    func testFinishWithoutPracticeOmitsPracticeEditedAndPostsNotification() {
        let spy = SpyAnalytics()
        let appState = typeAnywhereState(spy: spy)
        let posted = expectation(forNotification: .suniyeOnboardingDidFinish, object: appState)

        appState.finishOnboarding()

        wait(for: [posted], timeout: 1)
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertEqual(outcomeEvents(spy).first?.endedBy, .finishButton)
        XCTAssertNil(outcomeEvents(spy).first?.practiceEdited)
        XCTAssertNotNil(stepEvents(spy).first { $0.step == .completed }?.elapsedMs)
    }

    // MARK: - Window closed mid-onboarding

    func testWindowClosedRecordsStepAndElapsed() {
        let spy = SpyAnalytics()
        var now = Date(timeIntervalSince1970: 5_000)
        let appState = freshInstall(spy: spy, modelManager: StubModelManager(), progress: .speakReached, nowProvider: { now })
        appState.presentOnboardingIfNeeded()
        now = now.addingTimeInterval(12)

        appState.recordOnboardingWindowClosed()

        let closed = spy.trackedEvents.compactMap { event -> (OnboardingStepName, Int?)? in
            if case let .onboardingWindowClosed(step, elapsedMs) = event { return (step, elapsedMs) }
            return nil
        }
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed.first?.0, .speak)
        XCTAssertEqual(closed.first?.1, 12_000)
    }

    func testWindowClosedIsNoOpOutsideOnboarding() {
        let spy = SpyAnalytics()
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished)),
            analytics: spy
        )

        appState.recordOnboardingWindowClosed()

        XCTAssertFalse(spy.trackedEventNames.contains("onboarding_window_closed"))
    }
}
