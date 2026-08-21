import AVFoundation
import SuniyeAnalytics
import XCTest
@testable import Suniye

/// Funnel instrumentation and recovery-path tests for the redesigned
/// onboarding: microphone ask outcomes, model-download lifecycle events,
/// practice-dictation telemetry, and the post-onboarding Magic Format nudge.
@MainActor
final class AppStateOnboardingFunnelTests: XCTestCase {
    private func permissionRequests(_ spy: SpyAnalytics) -> [(kind: PermissionKind, surface: PermissionAskSurface, outcome: PermissionAskOutcome)] {
        spy.trackedEvents.compactMap {
            if case let .permissionRequest(kind, surface, outcome) = $0 {
                return (kind, surface, outcome)
            }
            return nil
        }
    }

    private func modelDownloads(_ spy: SpyAnalytics) -> [(kind: ModelKind, outcome: ModelDownloadOutcome, durationMs: Int?)] {
        spy.trackedEvents.compactMap {
            if case let .modelDownload(kind, _, outcome, durationMs) = $0 {
                return (kind, outcome, durationMs)
            }
            return nil
        }
    }

    private func practiceResults(_ spy: SpyAnalytics) -> [(outcome: PracticeOutcome, attempt: Int)] {
        spy.trackedEvents.compactMap {
            if case let .onboardingPracticeResult(outcome, attempt) = $0 {
                return (outcome, attempt)
            }
            return nil
        }
    }

    // MARK: - Microphone ask

    func testMicRequestFromNotDeterminedTracksGrantOutcome() async {
        let spy = SpyAnalytics()
        var status = AVAuthorizationStatus.notDetermined
        let appState = makeTestAppState(
            analytics: spy,
            micAuthorizationStatusProvider: { status },
            micAccessRequester: {
                status = .authorized
                return true
            }
        )

        await appState.refreshPermissions(requestMicrophone: true, askSurface: .onboarding)

        XCTAssertTrue(appState.hasMicPermission)
        XCTAssertFalse(appState.hasMicPermissionBeenDenied)
        let requests = permissionRequests(spy)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.last?.kind, .microphone)
        XCTAssertEqual(requests.last?.surface, .onboarding)
        XCTAssertEqual(requests.last?.outcome, .granted)
        XCTAssertTrue(spy.trackedEventNames.contains("permission_transition"))
    }

    func testMicRequestDenialTracksDeniedAndFlagsState() async {
        let spy = SpyAnalytics()
        var status = AVAuthorizationStatus.notDetermined
        let appState = makeTestAppState(
            analytics: spy,
            micAuthorizationStatusProvider: { status },
            micAccessRequester: {
                status = .denied
                return false
            }
        )

        await appState.refreshPermissions(requestMicrophone: true, askSurface: .onboarding)

        XCTAssertFalse(appState.hasMicPermission)
        XCTAssertTrue(appState.hasMicPermissionBeenDenied)
        XCTAssertEqual(permissionRequests(spy).last?.outcome, .denied)
    }

    func testAlreadyDeniedMicRequestDoesNotEmitAskEvent() async {
        // No system prompt can appear once denied — there is no "ask" to count.
        let spy = SpyAnalytics()
        let appState = makeTestAppState(
            analytics: spy,
            micAuthorizationStatusProvider: { .denied }
        )

        await appState.refreshPermissions(requestMicrophone: true, askSurface: .onboarding)

        XCTAssertTrue(appState.hasMicPermissionBeenDenied)
        XCTAssertTrue(permissionRequests(spy).isEmpty)
    }

    func testDeniedMicRoutesEnableButtonToSystemSettings() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(
            fileOpener: { url in
                openedURLs.append(url)
                return true
            },
            micAuthorizationStatusProvider: { .denied }
        )
        appState.hasMicPermissionBeenDenied = true

        appState.requestMicrophonePermission(askSurface: .onboarding)

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertTrue(openedURLs.first?.absoluteString.contains("Privacy_Microphone") == true)
    }

    func testDeniedMicAttentionFixOpensSettingsInsteadOfSilentNoop() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(
            fileOpener: { url in
                openedURLs.append(url)
                return true
            },
            micAuthorizationStatusProvider: { .denied }
        )
        appState.hasMicPermissionBeenDenied = true

        appState.handleAttentionFixAction(.requestMicrophonePermission)

        XCTAssertTrue(openedURLs.first?.absoluteString.contains("Privacy_Microphone") == true)
    }

    // MARK: - Practice does not gate on Accessibility

    func testPracticeRecordingStartsWithoutAccessibility() async {
        let audioCapture = StubAudioCaptureService()
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached))
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = false
        appState.startOnboardingIfNeeded()

        appState.startRecordingFromUI()

        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(appState.phase, .recording)
    }

    // MARK: - Practice telemetry

    private func runPracticeDictation(
        transcript: Result<String, Error>,
        spy: SpyAnalytics
    ) async -> AppState {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = transcript
        let started = expectation(description: "started")
        let transcribed = expectation(description: "transcribed")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        transcription.onTranscribe = { transcribed.fulfill() }

        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached)),
            analytics: spy
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.startOnboardingIfNeeded()

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await fulfillment(of: [transcribed], timeout: 1)
        for _ in 0 ..< 12 { await Task.yield() }
        return appState
    }

    func testSuccessfulPracticeEmitsDictationCompletedWithPracticeDestination() async {
        let spy = SpyAnalytics()
        let appState = await runPracticeDictation(transcript: .success("hello onboarding world"), spy: spy)

        XCTAssertTrue(appState.onboardingPracticeSucceeded)
        XCTAssertEqual(appState.onboardingPracticeAttempts, 1)
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .success)

        let results = practiceResults(spy)
        XCTAssertEqual(results.last?.outcome, .success)
        XCTAssertEqual(results.last?.attempt, 1)

        let metrics = spy.trackedEvents.compactMap { event -> DictationMetrics? in
            if case let .dictationCompleted(metrics) = event { return metrics }
            return nil
        }.last
        XCTAssertEqual(metrics?.destination, .onboardingPractice, "the dead enum value must be live for practice runs")
        XCTAssertEqual(metrics?.wordCount, 3)
    }

    func testEmptyPracticeEmitsEmptyAudioOutcomeAndCountsAttempt() async {
        let spy = SpyAnalytics()
        let appState = await runPracticeDictation(transcript: .success(""), spy: spy)

        XCTAssertFalse(appState.onboardingPracticeSucceeded)
        XCTAssertEqual(appState.onboardingPracticeAttempts, 1)
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .error)
        XCTAssertEqual(practiceResults(spy).last?.outcome, .emptyAudio)
    }

    func testFailedPracticeTranscriptionEmitsErrorOutcome() async {
        let spy = SpyAnalytics()
        _ = await runPracticeDictation(transcript: .failure(FakeError(message: "boom")), spy: spy)

        XCTAssertEqual(practiceResults(spy).last?.outcome, .error)
    }

    // MARK: - ASR model download lifecycle events

    func testASRDownloadEmitsStartedAndCompleted() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager, analytics: spy)
        appState.phase = .needsModel

        appState.startModelDownload()
        await waitUntilFunnel { appState.activeASRModelOperationID == nil }

        let downloads = modelDownloads(spy)
        XCTAssertEqual(downloads.first?.kind, .asr)
        XCTAssertEqual(downloads.first?.outcome, .started)
        XCTAssertTrue(downloads.contains { $0.outcome == .completed && $0.durationMs != nil })
    }

    func testASRDownloadFailureEmitsFailed() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        modelManager.downloadResult = .failure(FakeError(message: "offline"))
        let appState = makeTestAppState(modelManager: modelManager, analytics: spy)
        appState.phase = .needsModel

        appState.startModelDownload()
        await waitUntilFunnel { appState.phase == .error }

        XCTAssertTrue(modelDownloads(spy).contains { $0.kind == .asr && $0.outcome == .failed })
    }

    func testASRDownloadValidationFailureDoesNotEmitCompleted() async {
        let spy = SpyAnalytics()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        modelManager.installsModelAfterDownload = false
        let appState = makeTestAppState(modelManager: modelManager, analytics: spy)
        appState.phase = .needsModel

        appState.startModelDownload()
        await waitUntilFunnel { appState.phase == .error }

        let downloads = modelDownloads(spy)
        XCTAssertFalse(downloads.contains { $0.outcome == .completed })
        XCTAssertTrue(downloads.contains { $0.kind == .asr && $0.outcome == .failed })
    }

    func testASRDownloadCancelEmitsCanceledAndRestoresNeedsModel() async {
        let spy = SpyAnalytics()
        let modelManager = GatedModelManager()
        let appState = makeTestAppState(modelManager: modelManager, analytics: spy)
        appState.phase = .needsModel

        appState.startModelDownload()
        await waitUntilFunnel { appState.phase == .downloadingModel && appState.canCancelASRModelDownload }

        appState.cancelASRModelDownload()
        modelManager.gate.open()
        await waitUntilFunnel { appState.phase == .needsModel }

        XCTAssertTrue(modelDownloads(spy).contains { $0.kind == .asr && $0.outcome == .canceled })
        XCTAssertNil(appState.lastError)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testGemmaDownloadEmitsCleanupLifecycleEvents() async {
        let spy = SpyAnalytics()
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager, analytics: spy)

        appState.startLocalGemmaDownload()
        await waitUntilFunnel { appState.localGemmaInstallState.isInstalled }

        let downloads = modelDownloads(spy).filter { $0.kind == .cleanup }
        XCTAssertEqual(downloads.first?.outcome, .started)
        XCTAssertTrue(downloads.contains { $0.outcome == .completed })
    }

    // MARK: - Magic Format nudge

    private func nudgeReadyState(spy: SpyAnalytics = SpyAnalytics(), store: TestGeneralSettingsStore = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished))) -> AppState {
        let appState = makeTestAppState(generalSettingsStore: store, analytics: spy)
        appState.recentResults = (0 ..< 3).map {
            RecentResult(id: UUID(), text: "session \($0)", createdAt: Date(), durationSeconds: 2, wasLLMPolished: false)
        }
        return appState
    }

    func testNudgeAppearsAfterThreeDictations() {
        let appState = nudgeReadyState()
        XCTAssertTrue(appState.shouldShowMagicFormatNudge)

        appState.recentResults = Array(appState.recentResults.prefix(2))
        XCTAssertFalse(appState.shouldShowMagicFormatNudge)
    }

    func testNudgeHiddenWhenMFEnabledOrUnfinishedAndShownForAPIUsers() {
        let enabled = nudgeReadyState()
        enabled.llmEnabled = true
        XCTAssertFalse(enabled.shouldShowMagicFormatNudge)

        let unfinished = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .speakReached))
        )
        XCTAssertFalse(unfinished.shouldShowMagicFormatNudge)

        let apiUser = nudgeReadyState()
        apiUser.llmProvider = .openAICompatible
        XCTAssertTrue(apiUser.shouldShowMagicFormatNudge, "API users can still benefit from Magic Format")

        let unsupportedManager = StubLocalLLMModelManager()
        unsupportedManager.isHardwareSupported = false
        let unsupported = makeTestAppState(
            localLLMModelManager: unsupportedManager,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished))
        )
        unsupported.recentResults = (0 ..< 5).map {
            RecentResult(id: UUID(), text: "s\($0)", createdAt: Date(), durationSeconds: 1, wasLLMPolished: false)
        }
        XCTAssertTrue(unsupported.shouldShowMagicFormatNudge, "Local model availability must not hide the nudge")
    }

    func testNudgeImpressionTrackedOncePerRun() {
        let spy = SpyAnalytics()
        let appState = nudgeReadyState(spy: spy)

        appState.magicFormatNudgeDidShow()
        appState.magicFormatNudgeDidShow()

        XCTAssertEqual(spy.trackedEventNames.filter { $0 == "mf_nudge" }.count, 1)
    }

    func testNudgeDismissPersistsAndNeverReNags() {
        let spy = SpyAnalytics()
        let store = TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished))
        let appState = nudgeReadyState(spy: spy, store: store)

        appState.dismissMagicFormatNudge()

        XCTAssertFalse(appState.shouldShowMagicFormatNudge)
        XCTAssertEqual(store.latest.magicFormatNudgeDismissed, true)
        XCTAssertTrue(spy.trackedEventNames.contains("mf_nudge"))
    }

    func testNudgeOpenRoutesToMagicFormatPageAndRetiresCard() {
        let spy = SpyAnalytics()
        let appState = nudgeReadyState(spy: spy)

        let section = appState.openMagicFormatSetupFromNudge()

        XCTAssertEqual(section, .style)
        XCTAssertFalse(appState.shouldShowMagicFormatNudge)
        let actions = spy.trackedEvents.compactMap { event -> MFNudgeAction? in
            if case let .mfNudge(action) = event { return action }
            return nil
        }
        XCTAssertEqual(actions.last, .opened)
    }

    // MARK: - Download recovery details

    func testOfflineDownloadFailureGetsActionableCopy() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        modelManager.downloadResult = .failure(URLError(.notConnectedToInternet))
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .needsModel

        appState.startModelDownload()
        await waitUntilFunnel { appState.phase == .error }

        XCTAssertEqual(appState.lastError, "You appear to be offline. Reconnect and retry the download.")
    }

    func testTimedOutDownloadFailureGetsActionableCopy() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        modelManager.downloadResult = .failure(URLError(.timedOut))
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .needsModel

        appState.startModelDownload()
        await waitUntilFunnel { appState.phase == .error }

        XCTAssertEqual(appState.lastError, "The download timed out. Retry when your connection is stable.")
    }

    func testConnectionLostDownloadFailureGetsActionableCopy() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        modelManager.downloadResult = .failure(URLError(.networkConnectionLost))
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .needsModel

        appState.startModelDownload()
        await waitUntilFunnel { appState.phase == .error }

        XCTAssertEqual(appState.lastError, "The connection dropped mid-download. Retry to continue.")
    }

    func testCancelWithLoadedModelRestoresReadyPhase() async {
        // Cancelling a switch-download while another model is loaded must fall
        // back to the working model, not to needsModel.
        let spy = SpyAnalytics()
        let modelManager = GatedModelManager()
        let appState = makeTestAppState(modelManager: modelManager, analytics: spy)
        appState.loadedASRModelID = .parakeetV3
        appState.phase = .ready

        appState.startModelDownload()
        await waitUntilFunnel { appState.canCancelASRModelDownload }

        appState.cancelASRModelDownload()
        modelManager.gate.open()
        await waitUntilFunnel { appState.phase == .ready && appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertTrue(modelDownloads(spy).contains { $0.outcome == .canceled })
    }

    func testMicStatusFallsBackToRequesterAnswer() async {
        // Some providers only answer through the requester; a stale status read
        // must not lose a real grant.
        let appState = makeTestAppState(
            micAuthorizationStatusProvider: { .notDetermined },
            micAccessRequester: { true }
        )

        await appState.refreshPermissions(requestMicrophone: true, askSurface: .onboarding)

        XCTAssertTrue(appState.hasMicPermission)
    }

    func testOpenNotesDemoLaunchesNotes() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: { url in
            openedURLs.append(url)
            return true
        })

        appState.openNotesForInsertionDemo()

        XCTAssertTrue(openedURLs.first?.path.contains("Notes.app") == true)
    }

    // MARK: - Disk preflight message

    func testDiskShortfallMessageMentionsRequiredSpace() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(
            modelManager: modelManager,
            availableDiskCapacityProvider: { 10_000_000 }
        )
        appState.phase = .needsModel
        appState.startOnboardingIfNeeded()
        for _ in 0 ..< 100 where appState.onboardingDiskSpaceMessage == nil {
            await Task.yield()
        }

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertTrue(appState.onboardingDiskSpaceMessage?.contains("free") == true)
    }
}

/// Blocks the download until the test opens the gate, then honors task
/// cancellation — lets tests drive the in-flight-cancel path deterministically.
private final class GatedModelManager: ModelManagerProtocol {
    let gate = AsyncGate()
    private let backing = StubModelManager()

    init() {
        backing.installedModelIDs = []
    }

    var catalog: [ASRModelCatalogEntry] { backing.catalog }
    var fallbackOrder: [ASRModelID] { backing.fallbackOrder }
    func modelsRootDirectoryURL() throws -> URL { try backing.modelsRootDirectoryURL() }
    func modelDirectoryURL(for modelID: ASRModelID) throws -> URL { try backing.modelDirectoryURL(for: modelID) }
    func isInstalled(_ modelID: ASRModelID) -> Bool { backing.isInstalled(modelID) }
    func installedModels() -> [ASRModelID] { backing.installedModels() }
    func makeRecognizerConfig(for modelID: ASRModelID) throws -> RecognizerConfig { try backing.makeRecognizerConfig(for: modelID) }
    func expectedDownloadSizeBytes(for modelID: ASRModelID) -> Int64 { backing.expectedDownloadSizeBytes(for: modelID) }
    func installedByteCount(for modelID: ASRModelID) -> Int64 { backing.installedByteCount(for: modelID) }
    func deleteModel(_ modelID: ASRModelID) throws { try backing.deleteModel(modelID) }

    func downloadAndExtractModel(_ modelID: ASRModelID, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.1)
        await gate.wait()
        try Task.checkCancellation()
        progress(1)
    }
}

/// Local polling helper (the shared one lives in another file's fileprivate scope).
@MainActor
private func waitUntilFunnel(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ condition: @MainActor () -> Bool
) async {
    let start = DispatchTime.now().uptimeNanoseconds
    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
            return
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}
