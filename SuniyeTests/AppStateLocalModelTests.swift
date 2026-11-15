import XCTest
@testable import Suniye

@MainActor
final class AppStateLocalModelTests: XCTestCase {
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

    func testLocalGemmaDownloadReportsIntermediateProgress() async {
        let gate = AsyncGate()
        let manager = StubLocalLLMModelManager()
        manager.downloadGate = gate
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

        gate.open()
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
        let manager = StubLocalLLMModelManager()
        manager.deleteError = FakeError(message: "model file busy")
        manager.installedModelIDs = [manager.preferredModelID]
        let appState = makeTestAppState(localLLMModelManager: manager)
        appState.localGemmaInstallState = .installed(10)

        await appState.deleteLocalGemmaModel()

        XCTAssertEqual(appState.localGemmaInstallState, .failed("model file busy"))
    }

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
        let processor = ThrowingLocalGemmaPostProcessor(
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

    func testCurrentMagicFormatPromptURLFollowsProvider() {
        let promptStore = MagicFormatPromptFileStore(
            promptsDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("suniye-prompt-url-\(UUID().uuidString)", isDirectory: true)
        )
        let manager = StubLocalLLMModelManager()
        manager.installedModelIDs = [manager.preferredModelID]

        let appleState = makeTestAppState(
            appleMagicFormatPostProcessor: NoopAppleMagicFormatPostProcessor(availability: .available),
            magicFormatPromptFileStore: promptStore
        )
        appleState.llmProvider = .appleFoundationModels
        XCTAssertEqual(appleState.currentMagicFormatPromptURL, promptStore.providerPromptURL(.appleFoundationModels))

        let gemmaState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .available),
            localLLMModelManager: manager,
            magicFormatPromptFileStore: promptStore
        )
        gemmaState.llmProvider = .localGemma
        XCTAssertEqual(gemmaState.currentMagicFormatPromptURL, promptStore.providerPromptURL(.localGemma))

        let apiState = makeTestAppState(magicFormatPromptFileStore: promptStore)
        apiState.llmProvider = .openAICompatible
        XCTAssertEqual(apiState.currentMagicFormatPromptURL, promptStore.providerPromptURL(.openAICompatible))
    }

    func testChosenGemmaDownloadResumesAtBootstrap() async {
        // The user chose the local model during setup, the download died after
        // they moved on: bootstrap must self-heal instead of silently inserting
        // raw text forever.
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        await appState.bootstrap()
        await drainScheduledTasks(yields: 20)

        XCTAssertEqual(localManager.downloadCallCount, 1)
    }

    func testCanceledGemmaDownloadDoesNotResumeAtBootstrap() async {
        let localManager = StubLocalLLMModelManager()
        let settings = TestGeneralSettingsStore(
            value: GeneralSettings(localGemmaDownloadCancelled: true)
        )
        let appState = makeTestAppState(
            localLLMModelManager: localManager,
            generalSettingsStore: settings
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        await appState.bootstrap()

        XCTAssertEqual(localManager.downloadCallCount, 0)
    }

    func testGemmaResumeSkippedWhenInstalledOrNotChosen() {
        let installed = StubLocalLLMModelManager()
        installed.installedModelIDs.insert(installed.preferredModelID)
        let installedState = makeTestAppState(localLLMModelManager: installed)
        installedState.llmEnabled = true
        installedState.llmProvider = .localGemma
        installedState.resumeInterruptedLocalGemmaDownloadIfNeeded()
        XCTAssertEqual(installed.downloadCallCount, 0)

        let notChosen = StubLocalLLMModelManager()
        let notChosenState = makeTestAppState(localLLMModelManager: notChosen)
        notChosenState.llmEnabled = false
        notChosenState.llmProvider = .localGemma
        notChosenState.resumeInterruptedLocalGemmaDownloadIfNeeded()
        XCTAssertEqual(notChosen.downloadCallCount, 0)

        let unsupported = StubLocalLLMModelManager()
        unsupported.isHardwareSupported = false
        let unsupportedState = makeTestAppState(localLLMModelManager: unsupported)
        unsupportedState.llmEnabled = true
        unsupportedState.llmProvider = .localGemma
        unsupportedState.resumeInterruptedLocalGemmaDownloadIfNeeded()
        XCTAssertEqual(unsupported.downloadCallCount, 0)
    }

    func testColdLocalGemmaRequestShowsStartingIndicator() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            runtimeWarm: false,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.floatingIndicatorState = .processing()

        _ = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(appState.floatingIndicatorState, .processing(message: "Starting local model..."))
    }

    func testWarmLocalGemmaRequestShowsPolishingIndicator() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            runtimeWarm: true,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.floatingIndicatorState = .processing()

        _ = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(appState.floatingIndicatorState, .processing(message: "Polishing..."))
    }

    func testPrewarmEligibleForLocalGemmaTriggersPrewarm() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        await appState.prewarmLocalLLMIfEligible()?.value

        XCTAssertEqual(fakeGemma.prewarmCallCount, 1)
        XCTAssertEqual(fakeGemma.lastPrewarmConfig?.idleTimeoutSeconds, appState.localModelKeepAlive.seconds)
    }

    func testPrewarmSkippedWhenMagicFormatDisabled() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = false
        appState.llmProvider = .localGemma

        XCTAssertNil(appState.prewarmLocalLLMIfEligible())
        XCTAssertEqual(fakeGemma.prewarmCallCount, 0)
    }

    func testPrewarmSkippedWhenProviderNotLocal() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible

        XCTAssertNil(appState.prewarmLocalLLMIfEligible())
        XCTAssertEqual(fakeGemma.prewarmCallCount, 0)
    }

    func testPolishCancelsInFlightPrewarm() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            runtimeWarm: true,
            result: .success("gemma polished")
        )
        fakeGemma.prewarmBlocksUntilCanceled = true
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        let prewarm = appState.prewarmLocalLLMIfEligible()
        XCTAssertNotNil(prewarm)
        await waitUntil(timeout: 2) { fakeGemma.prewarmCallCount == 1 }

        let output = await appState.postProcessTextIfEnabled("raw text")
        await prewarm?.value

        XCTAssertEqual(output, "gemma polished")
        XCTAssertTrue(fakeGemma.prewarmWasCanceled)
    }

    func testNewPrewarmCancelsPriorInFlightPrewarm() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        fakeGemma.prewarmBlocksUntilCanceled = true
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        // First dictation is abandoned (no polish ever runs); its probe must not
        // survive into the next dictation's prewarm.
        let first = appState.prewarmLocalLLMIfEligible()
        await waitUntil(timeout: 2) { fakeGemma.prewarmCallCount == 1 }

        let second = appState.prewarmLocalLLMIfEligible()
        await first?.value
        XCTAssertTrue(fakeGemma.prewarmWasCanceled)

        await waitUntil(timeout: 2) { fakeGemma.prewarmCallCount == 2 }
        second?.cancel()
        await second?.value
    }

    func testPrewarmSkippedWhenLocalModelUnavailable() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .modelNotInstalled,
            result: .success("gemma polished")
        )
        let appState = makeTestAppState(localGemmaMagicFormatPostProcessor: fakeGemma)
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        XCTAssertNil(appState.prewarmLocalLLMIfEligible())
        XCTAssertEqual(fakeGemma.prewarmCallCount, 0)
    }

    func testExplicitLocalGemmaProviderUnavailableFallsBackToRaw() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .modelNotInstalled,
            result: .success("gemma polished")
        )
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            llmSettingsStore: store
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeGemma.callCount, 0)
        XCTAssertEqual(appState.magicFormatSetupState, .needsServiceSetup)
    }

    func testLocalGemmaNotInstalledShowsDownloadState() {
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)

        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        XCTAssertEqual(appState.localGemmaInstallState, .notInstalled)
        XCTAssertTrue(appState.canStartLocalGemmaDownload)
        XCTAssertEqual(appState.localGemmaMagicFormatAvailability, .modelNotInstalled)
        XCTAssertEqual(appState.magicFormatSetupState, .needsServiceSetup)
    }

    func testLocalGemmaDownloadUpdatesInstallState() async {
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)
        let downloadFinished = expectation(description: "local Gemma download finished")
        localManager.onDownloadFinished = {
            downloadFinished.fulfill()
        }

        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.startLocalGemmaDownload()
        await fulfillment(of: [downloadFinished], timeout: 1)
        await waitUntil(timeout: 1) {
            appState.localGemmaInstallState.isInstalled
        }

        XCTAssertEqual(localManager.downloadCallCount, 1)
        XCTAssertTrue(appState.localGemmaInstallState.isInstalled)
        XCTAssertFalse(appState.canStartLocalGemmaDownload)
    }

    func testLocalGemmaDownloadIgnoresStaleProgressAfterInstall() async {
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)
        let downloadFinished = expectation(description: "local Gemma download finished")
        localManager.onDownloadFinished = {
            downloadFinished.fulfill()
        }

        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.startLocalGemmaDownload()
        await fulfillment(of: [downloadFinished], timeout: 1)
        await waitUntil(timeout: 1) {
            appState.localGemmaInstallState.isInstalled
        }

        localManager.lastProgressHandler?(LocalLLMDownloadProgress(
            fractionCompleted: 1,
            downloadedBytes: LocalGemmaDefaults.modelEntry.expectedSizeBytes,
            expectedBytes: LocalGemmaDefaults.modelEntry.expectedSizeBytes
        ))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(appState.localGemmaInstallState.isInstalled)
    }

    func testLocalGemmaCancelForwardsToManager() {
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)
        appState.localGemmaInstallState = .downloading(LocalLLMDownloadProgress(
            fractionCompleted: 0.25,
            downloadedBytes: 25,
            expectedBytes: 100
        ))

        appState.cancelLocalGemmaDownload()

        XCTAssertEqual(localManager.cancelCallCount, 1)
    }

    func testLocalGemmaDeleteModelUpdatesInstallState() async {
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )

        XCTAssertTrue(appState.localGemmaInstallState.isInstalled)

        await appState.deleteLocalGemmaModel()

        XCTAssertEqual(fakeGemma.stopRuntimeCallCount, 1)
        XCTAssertEqual(localManager.deleteCallCount, 1)
        XCTAssertEqual(appState.localGemmaInstallState, .notInstalled)
    }

    func testLocalGemmaUnsupportedHardwareIsDisabled() {
        let localManager = StubLocalLLMModelManager()
        localManager.isHardwareSupported = false
        let appState = makeTestAppState(localLLMModelManager: localManager)

        XCTAssertFalse(appState.isLocalGemmaProviderSelectable)
        XCTAssertEqual(appState.localGemmaInstallState, .unavailable("Requires Apple Silicon."))
        XCTAssertEqual(appState.localGemmaMagicFormatAvailability, .unsupportedHardware)
    }

    func testLocalGemmaSetupTestDoesNotRequireAPIKey() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager,
            keychainService: TestKeychainService(value: nil)
        )

        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        await appState.testLocalGemmaSetup()

        XCTAssertNotNil(fakeGemma.lastConfig)
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "Local model works.")
        XCTAssertEqual(appState.magicFormatSetupTestResult?.severity, .success)
    }
}

/// Local Gemma post processor whose setup test always throws.
private final class ThrowingLocalGemmaPostProcessor: LocalGemmaMagicFormatPostProcessor {
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
