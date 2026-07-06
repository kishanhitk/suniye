import XCTest
@testable import Suniye

/// Coverage tests for ASR model lifecycle operations: download, select,
/// delete, bootstrap fallback, and their failure branches.
@MainActor
final class AppStateCoverageModelOpsTests: XCTestCase {
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Download

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
        XCTAssertEqual(appState.statusText, "Ready")
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
        XCTAssertEqual(appState.statusText, "Download failed")
        XCTAssertEqual(appState.lastError, "load exploded")
        XCTAssertEqual(appState.lastFailedASRModelID, .moonshineBase)
    }

    func testDownloadWithoutAutoSelectKeepsLoadedModelReady() async {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3

        appState.downloadASRModel(.moonshineBase, autoSelect: false)
        await waitUntil { appState.activeASRModelOperationID == nil }

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.statusText, "Ready")
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
        XCTAssertEqual(appState.statusText, "Model required")
    }

    func testDownloadValidationFailureSurfacesModelValidationError() async {
        let modelManager = CovModelOpsModelManager()
        modelManager.downloadSucceedsWithoutInstall = true
        modelManager.inner.installedModelIDs = []
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
        XCTAssertEqual(appState.statusText, "Download failed")
        XCTAssertEqual(appState.lastError, "network down")
        XCTAssertEqual(appState.downloadProgress, 0)
    }

    // MARK: - Select

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

    // MARK: - Delete

    func testDeleteIgnoredWhileRecording() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .recording

        appState.deleteASRModel(.parakeetV3)

        XCTAssertEqual(modelManager.deleteCallCount, 0)
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
        XCTAssertEqual(appState.statusText, "Load failed")
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
        let modelManager = CovModelOpsModelManager()
        modelManager.deleteError = FakeError(message: "disk locked")
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .ready

        appState.deleteASRModel(.parakeetV3)
        await waitUntil { appState.activeASRModelOperationID == nil && appState.phase == .error }

        XCTAssertEqual(appState.phase, .error)
        XCTAssertEqual(appState.statusText, "Model delete failed")
        XCTAssertEqual(appState.lastError, "disk locked")
        XCTAssertEqual(appState.lastFailedASRModelID, .parakeetV3)
        XCTAssertEqual(appState.lastFailedASRModelError, "disk locked")
    }

    // MARK: - Bootstrap failures

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
        XCTAssertEqual(appState.statusText, "Load failed")
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

    // MARK: - Wrappers

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

    func testStartModelDownloadAndDeleteModelUseSelectedModel() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .needsModel

        appState.startModelDownload()
        await waitUntil { appState.activeASRModelOperationID == nil }
        XCTAssertEqual(modelManager.lastDownloadedModelID, appState.selectedASRModelID)
        XCTAssertEqual(appState.phase, .ready)

        appState.deleteModel()
        await waitUntil { appState.activeASRModelOperationID == nil }
        XCTAssertEqual(modelManager.lastDeletedModelID, appState.selectedASRModelID)
        XCTAssertEqual(appState.phase, .needsModel)
    }

    func testOpenModelFolderFailureIsHandled() {
        let modelManager = CovModelOpsModelManager()
        modelManager.modelDirectoryURLError = FakeError(message: "no folder")
        let appState = makeTestAppState(modelManager: modelManager)

        // Throws inside and logs; must not crash or open anything.
        appState.openModelFolder()
        appState.openModelFolder(for: .moonshineBase)
    }

    // MARK: - System-managed (Apple Speech) UI helpers

    func testSystemManagedModelHidesSecondaryActionsAndShowsBuiltInSize() {
        let appState = makeTestAppState()

        XCTAssertEqual(appState.asrModelInstalledSizeText(for: .appleSpeech), "Built into macOS")
        XCTAssertFalse(
            appState.asrModelSecondaryActionsEnabled(for: .appleSpeech),
            "System-managed models have no folder to open and can't be deleted"
        )
        XCTAssertNotEqual(appState.asrModelInstalledSizeText(for: .parakeetV3), "Built into macOS")

        // Location label must not fabricate an on-disk path for a system-managed model.
        XCTAssertEqual(appState.asrModelLocationText(for: .appleSpeech), "Built into macOS")
        appState.selectedASRModelID = .appleSpeech
        XCTAssertEqual(appState.modelLocationText, "Built into macOS")
        XCTAssertTrue(appState.asrModelLocationText(for: .parakeetV3).contains("models"))
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
}

/// Model manager wrapper adding failure knobs on top of the shared stub.
private final class CovModelOpsModelManager: ModelManagerProtocol {
    let inner = StubModelManager()
    var deleteError: Error?
    var modelDirectoryURLError: Error?
    var downloadSucceedsWithoutInstall = false

    var catalog: [ASRModelCatalogEntry] { inner.catalog }
    var fallbackOrder: [ASRModelID] { inner.fallbackOrder }

    func modelsRootDirectoryURL() throws -> URL {
        try inner.modelsRootDirectoryURL()
    }

    func modelDirectoryURL(for modelID: ASRModelID) throws -> URL {
        if let modelDirectoryURLError {
            throw modelDirectoryURLError
        }
        return try inner.modelDirectoryURL(for: modelID)
    }

    func isInstalled(_ modelID: ASRModelID) -> Bool {
        inner.isInstalled(modelID)
    }

    func installedModels() -> [ASRModelID] {
        inner.installedModels()
    }

    func makeRecognizerConfig(for modelID: ASRModelID) throws -> RecognizerConfig {
        try inner.makeRecognizerConfig(for: modelID)
    }

    func downloadAndExtractModel(_ modelID: ASRModelID, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
        if downloadSucceedsWithoutInstall {
            return
        }
        try await inner.downloadAndExtractModel(modelID) { _ in }
    }

    func expectedDownloadSizeBytes(for modelID: ASRModelID) -> Int64 {
        inner.expectedDownloadSizeBytes(for: modelID)
    }

    func installedByteCount(for modelID: ASRModelID) -> Int64 {
        inner.installedByteCount(for: modelID)
    }

    func deleteModel(_ modelID: ASRModelID) throws {
        if let deleteError {
            throw deleteError
        }
        try inner.deleteModel(modelID)
    }
}
