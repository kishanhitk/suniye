import XCTest
@testable import Suniye

/// Coverage tests for the local Gemma Magic Format provider: install state
/// text, download lifecycle, delete failures, setup tests, and provider
/// detail strings.
@MainActor
final class AppStateCoverageLocalGemmaTests: XCTestCase {
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

    // MARK: - Install state display

    func testLocalGemmaInstallStatusTextBranches() {
        let manager = StubLocalLLMModelManager()
        manager.installedModelIDs = [manager.preferredModelID]
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .available),
            localLLMModelManager: manager
        )

        appState.localGemmaInstallState = .unavailable("Needs Apple Silicon")
        XCTAssertEqual(appState.localGemmaInstallStatusText, "Needs Apple Silicon")

        appState.localGemmaInstallState = .notInstalled
        XCTAssertEqual(appState.localGemmaInstallStatusText, "Local model not installed.")

        appState.localGemmaInstallState = .downloading(LocalLLMDownloadProgress(
            fractionCompleted: 0.5,
            downloadedBytes: 500_000,
            expectedBytes: 1_000_000
        ))
        XCTAssertTrue(appState.localGemmaInstallStatusText.contains("downloaded"))
        XCTAssertEqual(appState.localGemmaInstallProgress, 0.5)

        appState.localGemmaInstallState = .verifying
        XCTAssertEqual(appState.localGemmaInstallStatusText, "Verifying local model...")
        XCTAssertNil(appState.localGemmaInstallProgress)

        appState.localGemmaInstallState = .installed(1_000_000)
        XCTAssertEqual(appState.localGemmaInstallStatusText, "Local model ready.")

        appState.localGemmaInstallState = .failed("Download canceled.")
        XCTAssertEqual(appState.localGemmaInstallStatusText, "Download canceled.")
    }

    func testLocalGemmaInstalledButRuntimeUnavailableShowsSizeAndStatus() {
        let manager = StubLocalLLMModelManager()
        manager.installedModelIDs = [manager.preferredModelID]
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .runtimeUnavailable),
            localLLMModelManager: manager
        )

        appState.localGemmaInstallState = .installed(2_000_000)
        XCTAssertTrue(appState.localGemmaInstallStatusText.contains("installed."))
        XCTAssertTrue(appState.localGemmaInstallStatusText.contains("runtime is not available"))
    }

    func testLocalGemmaDownloadAvailabilityFlags() {
        let manager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: manager)

        appState.localGemmaInstallState = .notInstalled
        XCTAssertTrue(appState.canStartLocalGemmaDownload)
        XCTAssertFalse(appState.canCancelLocalGemmaDownload)
        XCTAssertFalse(appState.canDeleteLocalGemmaModel)

        appState.localGemmaInstallState = .downloading(LocalLLMDownloadProgress(
            fractionCompleted: 0.2,
            downloadedBytes: 1,
            expectedBytes: 10
        ))
        XCTAssertFalse(appState.canStartLocalGemmaDownload)
        XCTAssertTrue(appState.canCancelLocalGemmaDownload)
        XCTAssertFalse(appState.canDeleteLocalGemmaModel)

        appState.localGemmaInstallState = .installed(10)
        XCTAssertFalse(appState.canStartLocalGemmaDownload)
        XCTAssertTrue(appState.canDeleteLocalGemmaModel)

        manager.isHardwareSupported = false
        appState.localGemmaInstallState = .notInstalled
        XCTAssertFalse(appState.canStartLocalGemmaDownload)
        XCTAssertFalse(appState.isLocalGemmaProviderSelectable)
    }

    func testRefreshLocalGemmaInstallStateSkippedWhileActive() {
        let manager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: manager)

        let downloading = LocalLLMInstallState.downloading(LocalLLMDownloadProgress(
            fractionCompleted: 0.4,
            downloadedBytes: 4,
            expectedBytes: 10
        ))
        appState.localGemmaInstallState = downloading

        appState.refreshLocalGemmaInstallState()

        XCTAssertEqual(appState.localGemmaInstallState, downloading)
    }

    // MARK: - Download lifecycle

    func testLocalGemmaDownloadReportsIntermediateProgress() async {
        let manager = CovLocalGemmaManager()
        let appState = makeTestAppState(localLLMModelManager: manager)
        appState.localGemmaInstallState = .notInstalled

        appState.startLocalGemmaDownload()
        await waitUntil {
            if case let .downloading(progress) = appState.localGemmaInstallState {
                return progress.fractionCompleted == 0.5
            }
            return false
        }
        if case let .downloading(progress) = appState.localGemmaInstallState {
            XCTAssertEqual(progress.fractionCompleted, 0.5)
        } else {
            XCTFail("expected mid-download state, got \(appState.localGemmaInstallState)")
        }

        manager.finishDownload()
        await waitUntil { appState.localGemmaInstallState.isInstalled }
        XCTAssertTrue(appState.localGemmaInstallState.isInstalled)
    }

    func testLocalGemmaDownloadCancellationShowsCanceledMessage() async {
        let manager = StubLocalLLMModelManager()
        manager.downloadResult = .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        let appState = makeTestAppState(localLLMModelManager: manager)
        appState.localGemmaInstallState = .notInstalled

        appState.startLocalGemmaDownload()
        await waitUntil {
            if case .failed = appState.localGemmaInstallState {
                return true
            }
            return false
        }

        XCTAssertEqual(appState.localGemmaInstallState, .failed("Download canceled."))
    }

    func testLocalGemmaDownloadFailureShowsErrorMessage() async {
        let manager = StubLocalLLMModelManager()
        manager.downloadResult = .failure(FakeError(message: "server unreachable"))
        let appState = makeTestAppState(localLLMModelManager: manager)
        appState.localGemmaInstallState = .notInstalled

        appState.startLocalGemmaDownload()
        await waitUntil {
            if case .failed = appState.localGemmaInstallState {
                return true
            }
            return false
        }

        XCTAssertEqual(appState.localGemmaInstallState, .failed("server unreachable"))
    }

    func testCancelLocalGemmaDownloadIgnoredWhenNotDownloading() {
        let manager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: manager)
        appState.localGemmaInstallState = .notInstalled

        appState.cancelLocalGemmaDownload()

        XCTAssertEqual(manager.cancelCallCount, 0)
    }

    func testDeleteLocalGemmaModelIgnoredWhileActive() async {
        let manager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: manager)
        appState.localGemmaInstallState = .verifying

        await appState.deleteLocalGemmaModel()

        XCTAssertEqual(manager.deleteCallCount, 0)
    }

    func testDeleteLocalGemmaModelFailureShowsError() async {
        let manager = CovLocalGemmaManager()
        manager.deleteError = FakeError(message: "model file busy")
        manager.installedModelIDs = [manager.preferredModelID]
        let appState = makeTestAppState(localLLMModelManager: manager)
        appState.localGemmaInstallState = .installed(10)

        await appState.deleteLocalGemmaModel()

        XCTAssertEqual(appState.localGemmaInstallState, .failed("model file busy"))
    }

    // MARK: - Local setup test

    func testTestLocalGemmaSetupRequiresEnabledLocalProvider() async {
        let appState = makeTestAppState()
        appState.llmEnabled = false

        await appState.testLocalGemmaSetup()

        XCTAssertNil(appState.magicFormatSetupTestResult)
    }

    func testTestLocalGemmaSetupRequiresInstalledModel() async {
        let appState = makeTestAppState()
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.localGemmaInstallState = .notInstalled

        await appState.testLocalGemmaSetup()

        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(message: "Download the local model first.", severity: .error)
        )
    }

    private func runLocalGemmaSetupTest(error: Error) async -> AppState {
        let manager = StubLocalLLMModelManager()
        manager.installedModelIDs = [manager.preferredModelID]
        let processor = CovThrowingLocalGemmaPostProcessor(
            availability: .available,
            testSetupError: error
        )
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: processor,
            localLLMModelManager: manager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.localGemmaInstallState = .installed(10)
        await appState.testLocalGemmaSetup()
        return appState
    }

    func testTestLocalGemmaSetupMapsErrors() async {
        var appState = await runLocalGemmaSetupTest(error: LLMPostProcessorError.timeout)
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "Local model took too long to respond.")
        XCTAssertEqual(appState.magicFormatSetupTestResult?.severity, .error)

        appState = await runLocalGemmaSetupTest(error: LLMPostProcessorError.invalidConfiguration("bad"))
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, LocalGemmaAvailability.available.statusText)

        appState = await runLocalGemmaSetupTest(error: LLMPostProcessorError.provider("500"))
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "Local model responded, but not in a compatible format.")

        appState = await runLocalGemmaSetupTest(error: LLMPostProcessorError.network("down"))
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "Couldn't reach the local model server.")

        appState = await runLocalGemmaSetupTest(error: LLMPostProcessorError.unauthorized)
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "Local model rejected the local authorization token.")

        appState = await runLocalGemmaSetupTest(error: FakeError(message: "weird failure"))
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "weird failure")
    }

    func testTestLocalGemmaSetupSuccess() async {
        let manager = StubLocalLLMModelManager()
        manager.installedModelIDs = [manager.preferredModelID]
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .available),
            localLLMModelManager: manager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.localGemmaInstallState = .installed(10)

        await appState.testLocalGemmaSetup()

        // Assert the meaningful fields, not the whole struct: the result also
        // carries a measured latency, which is not deterministic in a test.
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "Local model works.")
        XCTAssertEqual(appState.magicFormatSetupTestResult?.severity, .success)
    }

    // MARK: - Provider detail text and key status

    func testMagicFormatProviderDetailTextBranches() {
        let manager = StubLocalLLMModelManager()
        manager.installedModelIDs = [manager.preferredModelID]

        // Automatic with Apple available.
        let appleState = makeTestAppState(
            appleMagicFormatPostProcessor: NoopAppleMagicFormatPostProcessor(availability: .available)
        )
        appleState.llmProvider = .automatic
        XCTAssertEqual(appleState.magicFormatProviderDetailText, "Using Apple Intelligence locally.")

        // Automatic with only the local model available.
        let gemmaState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .available),
            localLLMModelManager: manager
        )
        gemmaState.llmProvider = .automatic
        XCTAssertEqual(gemmaState.magicFormatProviderDetailText, "Using local model.")

        // Automatic with no local providers.
        let apiState = makeTestAppState()
        apiState.llmProvider = .automatic
        XCTAssertTrue(apiState.magicFormatProviderDetailText.contains("Local providers unavailable"))

        // Explicit providers.
        apiState.llmProvider = .appleFoundationModels
        XCTAssertEqual(apiState.magicFormatProviderDetailText, AppleFoundationModelsAvailability.unsupportedSDKOrRuntime.statusText)

        apiState.llmProvider = .localGemma
        XCTAssertEqual(apiState.magicFormatProviderDetailText, apiState.localGemmaInstallStatusText)

        apiState.llmProvider = .openAICompatible
        XCTAssertEqual(apiState.magicFormatProviderDetailText, "Using your OpenAI-compatible endpoint.")
    }

    func testLLMKeyStatusTextLocalProviderBranches() {
        let manager = StubLocalLLMModelManager()
        manager.installedModelIDs = [manager.preferredModelID]

        let gemmaReady = makeTestAppState(
            localGemmaMagicFormatPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .available),
            localLLMModelManager: manager
        )
        gemmaReady.llmProvider = .localGemma
        XCTAssertEqual(gemmaReady.llmKeyStatusText, "Ready")

        let gemmaMissing = makeTestAppState()
        gemmaMissing.llmProvider = .localGemma
        XCTAssertEqual(gemmaMissing.llmKeyStatusText, "Unavailable")

        let appleReady = makeTestAppState(
            appleMagicFormatPostProcessor: NoopAppleMagicFormatPostProcessor(availability: .available)
        )
        appleReady.llmProvider = .appleFoundationModels
        XCTAssertEqual(appleReady.llmKeyStatusText, "Ready")

        let appleMissing = makeTestAppState()
        appleMissing.llmProvider = .appleFoundationModels
        XCTAssertEqual(appleMissing.llmKeyStatusText, "Unavailable")
    }

    func testCurrentMagicFormatPromptURLFollowsProvider() {
        let promptStore = MagicFormatPromptFileStore(
            promptsDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("cov-prompt-url-\(UUID().uuidString)", isDirectory: true)
        )
        let manager = StubLocalLLMModelManager()
        manager.installedModelIDs = [manager.preferredModelID]

        let appleState = makeTestAppState(
            appleMagicFormatPostProcessor: NoopAppleMagicFormatPostProcessor(availability: .available),
            magicFormatPromptFileStore: promptStore
        )
        appleState.llmProvider = .appleFoundationModels
        XCTAssertEqual(appleState.currentMagicFormatPromptURL, promptStore.providerPromptURL(.apple))

        let gemmaState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .available),
            localLLMModelManager: manager,
            magicFormatPromptFileStore: promptStore
        )
        gemmaState.llmProvider = .localGemma
        XCTAssertEqual(gemmaState.currentMagicFormatPromptURL, promptStore.providerPromptURL(.localGemma))

        let apiState = makeTestAppState(magicFormatPromptFileStore: promptStore)
        apiState.llmProvider = .openAICompatible
        XCTAssertEqual(apiState.currentMagicFormatPromptURL, promptStore.providerPromptURL(.api))
    }

    func testLocalGemmaModelEntryComesFromCatalog() {
        let manager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: manager)
        XCTAssertEqual(appState.localGemmaModelEntry.id, manager.preferredModelID)
    }
}

/// Local LLM manager that suspends downloads mid-flight and supports delete failures.
private final class CovLocalGemmaManager: LocalLLMModelManagerProtocol {
    var catalog: [LocalLLMModelCatalogEntry] = LocalLLMModelCatalog.entries
    var preferredModelID: LocalLLMModelID = LocalLLMModelCatalog.preferredModelID
    var isHardwareSupported = true
    var installedModelIDs: Set<LocalLLMModelID> = []
    var deleteError: Error?
    private var downloadContinuation: CheckedContinuation<Void, Never>?

    func modelsRootDirectoryURL() throws -> URL {
        URL(fileURLWithPath: "/tmp/cov-suniye-llm", isDirectory: true)
    }

    func modelFileURL(for modelID: LocalLLMModelID) throws -> URL {
        try modelsRootDirectoryURL().appendingPathComponent(modelID.rawValue)
    }

    func isInstalled(_ modelID: LocalLLMModelID) -> Bool {
        isHardwareSupported && installedModelIDs.contains(modelID)
    }

    func installedByteCount(for modelID: LocalLLMModelID) -> Int64 {
        isInstalled(modelID) ? 1_000_000 : 0
    }

    func installState(for modelID: LocalLLMModelID) -> LocalLLMInstallState {
        guard isHardwareSupported else {
            return .unavailable("Requires Apple Silicon.")
        }
        return isInstalled(modelID) ? .installed(installedByteCount(for: modelID)) : .notInstalled
    }

    func downloadModel(_ modelID: LocalLLMModelID, progress: @escaping @Sendable (LocalLLMDownloadProgress) -> Void) async throws {
        progress(LocalLLMDownloadProgress(fractionCompleted: 0.5, downloadedBytes: 500, expectedBytes: 1000))
        await withCheckedContinuation { continuation in
            downloadContinuation = continuation
        }
        installedModelIDs.insert(modelID)
    }

    func finishDownload() {
        downloadContinuation?.resume()
        downloadContinuation = nil
    }

    func cancelDownload() {}

    func deleteModel(_ modelID: LocalLLMModelID) throws {
        if let deleteError {
            throw deleteError
        }
        installedModelIDs.remove(modelID)
    }
}

/// Local Gemma post processor whose setup test always throws.
private final class CovThrowingLocalGemmaPostProcessor: LocalGemmaMagicFormatPostProcessor {
    var availability: LocalGemmaAvailability
    private let testSetupError: Error

    init(availability: LocalGemmaAvailability, testSetupError: Error) {
        self.availability = availability
        self.testSetupError = testSetupError
    }

    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        text
    }

    func generate(instructions: String, userText: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        userText
    }

    func testSetup(config: LocalGemmaMagicFormatConfig) async throws {
        throw testSetupError
    }
}
