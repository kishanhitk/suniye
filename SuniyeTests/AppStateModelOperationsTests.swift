import XCTest
@testable import Suniye

@MainActor
final class AppStateModelOperationsTests: XCTestCase {
    func testDownloadIgnoredWhileRecording() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .recording

        appState.downloadASRModel(.moonshineBase, autoSelect: true)

        XCTAssertNil(appState.activeASRModelOperationID)
        XCTAssertNil(modelManager.lastDownloadedModelID)
        XCTAssertEqual(appState.phase, .recording)
    }

    func testDownloadAutoSelectLoadFailureFallsBackToReadyWhenModelLoaded() async {
        let modelManager = StubModelManager()
        let transcription = StubTranscriptionService()
        transcription.loadModelErrorsByModelID[.moonshineBase] = FakeError(message: "load exploded")
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription
        )
        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3

        appState.downloadASRModel(.moonshineBase, autoSelect: true)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.lastFailedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.lastFailedASRModelError, "load exploded")
    }

    func testDownloadAutoSelectLoadFailureWithoutLoadedModelEntersErrorPhase() async {
        let modelManager = StubModelManager()
        let transcription = StubTranscriptionService()
        transcription.loadModelErrorsByModelID[.moonshineBase] = FakeError(message: "load exploded")
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription
        )
        appState.phase = .ready

        appState.downloadASRModel(.moonshineBase, autoSelect: true)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .error)
        XCTAssertEqual(appState.lastError, "load exploded")
        XCTAssertEqual(appState.lastFailedASRModelID, .moonshineBase)
    }

    func testDownloadRefusesWhenDiskSpaceIsShortOfTwiceTheDownload() async {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(
            modelManager: modelManager,
            availableDiskCapacityProvider: { 1_000 }
        )
        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3

        appState.downloadASRModel(.cohereTranscribe, autoSelect: true)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertNil(modelManager.lastDownloadedModelID, "the download must not start")
        XCTAssertEqual(appState.phase, .ready, "the loaded model keeps working")
        XCTAssertEqual(appState.lastFailedASRModelID, .cohereTranscribe)
        let needed = ByteCountFormatter.string(fromByteCount: ASRModelCatalog.entry(for: .cohereTranscribe).estimatedSizeBytes * 2, countStyle: .file)
        XCTAssertEqual(appState.lastFailedASRModelError, "Not enough free disk space — the speech model needs about \(needed) free.")
    }

    func testDownloadWithoutAutoSelectKeepsLoadedModelReady() async {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3

        appState.downloadASRModel(.moonshineBase, autoSelect: false)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.loadedASRModelID, .parakeetV3)
        XCTAssertTrue(modelManager.installedModelIDs.contains(.moonshineBase))
        XCTAssertNil(appState.lastFailedASRModelID)
    }

    func testDownloadWithoutAutoSelectWithoutLoadedModelRequiresModel() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .needsModel

        appState.downloadASRModel(.moonshineBase, autoSelect: false)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .needsModel)
    }

    func testDownloadValidationFailureSurfacesModelValidationError() async {
        let modelManager = StubModelManager()
        modelManager.installsModelAfterDownload = false
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .needsModel

        appState.downloadASRModel(.moonshineBase, autoSelect: true)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .error)
        XCTAssertEqual(appState.lastError, "Model files are missing after extraction.")
        XCTAssertEqual(appState.lastFailedASRModelID, .moonshineBase)
    }

    func testDownloadNetworkFailureEntersErrorPhase() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        modelManager.downloadResult = .failure(FakeError(message: "network down"))
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .needsModel

        appState.downloadASRModel(.parakeetV3, autoSelect: true)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .error)
        XCTAssertEqual(appState.lastError, "network down")
        XCTAssertEqual(appState.downloadProgress, 0)
    }

    func testSelectIgnoredWhileRecordingOrAlreadyLoaded() {
        let appState = makeTestAppState()
        appState.phase = .recording
        appState.selectASRModel(.moonshineBase)
        XCTAssertNil(appState.activeASRModelOperationID)

        appState.phase = .ready
        appState.loadedASRModelID = .moonshineBase
        appState.selectASRModel(.moonshineBase)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testSelectUninstalledModelDownloadsIt() async {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .ready

        appState.selectASRModel(.moonshineBase)
        await waitUntil { appState.activeASRModelOperationID == nil && appState.phase == .ready }

        XCTAssertEqual(modelManager.lastDownloadedModelID, .moonshineBase)
        XCTAssertEqual(appState.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.loadedASRModelID, .moonshineBase)
    }

    func testSelectInstalledModelLoadFailureFallsBackToReady() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .moonshineBase]
        let transcription = StubTranscriptionService()
        transcription.loadModelErrorsByModelID[.moonshineBase] = FakeError(message: "switch failed")
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription
        )
        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3

        appState.selectASRModel(.moonshineBase)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.lastFailedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.lastFailedASRModelError, "switch failed")
        XCTAssertEqual(appState.loadedASRModelID, .parakeetV3)
    }

    func testDeleteIgnoredWhileRecording() {
        let appState = makeTestAppState()
        appState.phase = .recording

        appState.deleteASRModel(.parakeetV3)

        XCTAssertNil(appState.activeASRModelOperationID)
        XCTAssertEqual(appState.phase, .recording)
    }

    func testDeleteCurrentModelWithFailingFallbackEntersErrorPhase() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .moonshineBase]
        let transcription = StubTranscriptionService()
        transcription.loadModelErrorsByModelID[.moonshineBase] = FakeError(message: "fallback broke")
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription
        )
        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3

        appState.deleteASRModel(.parakeetV3)
        await waitUntil { appState.activeASRModelOperationID == nil && appState.phase == .error }

        XCTAssertEqual(appState.phase, .error)
        XCTAssertTrue(appState.lastError?.contains("fallback broke") == true)
        XCTAssertEqual(transcription.unloadCallCount, 1)
    }

    func testDeleteNonCurrentModelClearsLastError() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .moonshineBase]
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3
        appState.lastError = "stale error"

        appState.deleteASRModel(.moonshineBase)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(modelManager.lastDeletedModelID, .moonshineBase)
        XCTAssertEqual(appState.loadedASRModelID, .parakeetV3)
    }

    func testDeleteFailureSurfacesError() async {
        let modelManager = StubModelManager()
        modelManager.deleteError = FakeError(message: "disk locked")
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .ready

        appState.deleteASRModel(.parakeetV3)
        await waitUntil { appState.activeASRModelOperationID == nil && appState.phase == .error }

        XCTAssertEqual(appState.phase, .error)
        XCTAssertEqual(appState.lastError, "disk locked")
        XCTAssertEqual(appState.lastFailedASRModelID, .parakeetV3)
        XCTAssertEqual(appState.lastFailedASRModelError, "disk locked")
    }

    func testBootstrapLoadFailureEntersErrorPhase() async {
        let modelManager = StubModelManager()
        let transcription = StubTranscriptionService()
        transcription.loadModelResult = .failure(FakeError(message: "bootstrap broke"))
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription
        )

        await appState.bootstrap()

        XCTAssertEqual(appState.phase, .error)
        XCTAssertTrue(appState.lastError?.contains("bootstrap broke") == true)
        XCTAssertNil(appState.activeASRModelOperationID)
    }

    func testBootstrapTriesEveryInstalledCandidateBeforeFailing() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .moonshineBase]
        let transcription = StubTranscriptionService()
        transcription.loadModelResult = .failure(FakeError(message: "all models broke"))
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription
        )

        await appState.bootstrap()

        XCTAssertEqual(appState.phase, .error)
        XCTAssertEqual(transcription.loadCallCount, 2)
        XCTAssertTrue(appState.lastError?.contains("all models broke") == true)
    }

    func testPerformPrimaryASRActionBranches() async {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .ready

        // Blocked while another operation is active.
        appState.activeASRModelOperationID = .parakeetV3
        appState.performPrimaryASRAction(for: .moonshineBase)
        XCTAssertNil(modelManager.lastDownloadedModelID)
        appState.activeASRModelOperationID = nil

        // Missing model downloads.
        appState.performPrimaryASRAction(for: .moonshineBase)
        await waitUntil { appState.activeASRModelOperationID == nil && appState.phase == .ready }
        XCTAssertEqual(modelManager.lastDownloadedModelID, .moonshineBase)

        // Installed-but-not-loaded model switches via select.
        appState.performPrimaryASRAction(for: .parakeetV3)
        await waitUntil { appState.activeASRModelOperationID == nil && appState.loadedASRModelID == .parakeetV3 }
        XCTAssertEqual(appState.selectedASRModelID, .parakeetV3)
    }

    func testSystemManagedModelHidesSecondaryActionsAndShowsBuiltInSize() {
        let appState = makeTestAppState()

        XCTAssertEqual(appState.asrModelInstalledSizeText(for: .appleSpeech), "Built into macOS")
        XCTAssertFalse(
            appState.asrModelSecondaryActionsEnabled(for: .appleSpeech),
            "System-managed models have no folder to open and can't be deleted"
        )
        XCTAssertNotEqual(appState.asrModelInstalledSizeText(for: .parakeetV3), "Built into macOS")
    }

    func testPrimaryActionForSystemManagedDownloadsAssetThenSelects() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3] // Apple asset NOT present → needs download
        let transcription = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcription)
        appState.phase = .ready

        appState.performPrimaryASRAction(for: .appleSpeech)
        await waitUntil { appState.selectedASRModelID == .appleSpeech && appState.phase == .ready }

        XCTAssertEqual(appState.selectedASRModelID, .appleSpeech)
        XCTAssertEqual(modelManager.lastDownloadedModelID, .appleSpeech, "an absent asset must be downloaded with progress")
        XCTAssertEqual(transcription.loadCallCount, 1)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testPrimaryActionForSystemManagedSkipsDownloadWhenAssetPresent() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .appleSpeech] // asset already present
        let transcription = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcription)
        appState.phase = .ready

        appState.performPrimaryASRAction(for: .appleSpeech)
        await waitUntil { appState.selectedASRModelID == .appleSpeech && appState.phase == .ready }

        XCTAssertNil(modelManager.lastDownloadedModelID, "a present asset must not trigger a download")
        XCTAssertEqual(transcription.loadCallCount, 1)
        XCTAssertEqual(appState.selectedASRModelID, .appleSpeech)
    }

    func testASRModelReadyRequiresInstalledAndUsablePhase() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.phase = .loading
        XCTAssertFalse(appState.asrModelReady)

        appState.phase = .ready
        XCTAssertTrue(appState.asrModelReady)

        appState.phase = .recording
        XCTAssertTrue(appState.asrModelReady)

        modelManager.installedModelIDs = []
        XCTAssertFalse(appState.asrModelReady)
    }

    func testDeleteModelTransitionsToNeedsModel() async {
        let modelManager = StubModelManager()
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready

        appState.deleteModel()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.deleteCallCount, 1)
        XCTAssertEqual(modelManager.lastDeletedModelID, appState.selectedASRModelID)
        XCTAssertEqual(transcriptionService.unloadCallCount, 1)
        XCTAssertEqual(appState.phase, .needsModel)
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
    }

    func testSelectingInstalledASRModelLoadsRecognizerAndPersistsSelection() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice]
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.selectASRModel(.senseVoice)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.selectedASRModelID, .senseVoice)
        XCTAssertEqual(appState.loadedASRModelID, .senseVoice)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(transcriptionService.loadedConfigs.last?.modelID, .senseVoice)
    }

    func testBootstrapFallsBackToAnotherInstalledModelWhenPreferredLoadFails() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice, .moonshineBase]
        let transcriptionService = StubTranscriptionService()
        transcriptionService.loadModelErrorsByModelID = [
            .parakeetV3: FakeError(message: "selected broken"),
            .senseVoice: FakeError(message: "fallback broken")
        ]
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: true,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            generalSettingsStore: generalSettingsStore
        )

        await appState.bootstrap()

        XCTAssertEqual(appState.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.loadedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(generalSettingsStore.latest.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(transcriptionService.loadedConfigs.map(\.modelID), [.parakeetV3, .senseVoice, .moonshineBase])
    }

    func testDeletingCurrentASRModelFallsBackToInstalledAlternative() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice]
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.deleteASRModel(.parakeetV3)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDeletedModelID, .parakeetV3)
        XCTAssertEqual(appState.selectedASRModelID, .senseVoice)
        XCTAssertEqual(appState.loadedASRModelID, .senseVoice)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testDeletingCurrentASRModelSkipsBrokenFallbackAndPersistsSuccessfulAlternative() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice, .moonshineBase]
        let transcriptionService = StubTranscriptionService()
        transcriptionService.loadModelErrorsByModelID = [
            .senseVoice: FakeError(message: "fallback broken")
        ]
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: true,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            generalSettingsStore: generalSettingsStore
        )
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.deleteASRModel(.parakeetV3)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDeletedModelID, .parakeetV3)
        XCTAssertEqual(appState.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.loadedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(generalSettingsStore.latest.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(transcriptionService.loadedConfigs.map(\.modelID), [.senseVoice, .moonshineBase])
    }
}
