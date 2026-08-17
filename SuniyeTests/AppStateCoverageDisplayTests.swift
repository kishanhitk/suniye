import SwiftUI
import XCTest
@testable import Suniye

/// Coverage tests for AppState display-oriented enums and computed status
/// properties (model status text/color/icon, banners, download ETA, launch
/// at login, app version).
@MainActor
final class AppStateCoverageDisplayTests: XCTestCase {
    // MARK: - Small display enums

    func testLLME2EModeLogValues() {
        XCTAssertEqual(LLME2EMode.none.logValue, "none")
        XCTAssertEqual(LLME2EMode.forceSuccess.logValue, "success")
        XCTAssertEqual(LLME2EMode.forceFailure.logValue, "fallback")
    }

    func testMagicFormatSetupStateDisplayProperties() {
        XCTAssertEqual(MagicFormatSetupState.off.title, "Off")
        XCTAssertEqual(MagicFormatSetupState.needsAPIKey.title, "Needs API key")
        XCTAssertEqual(MagicFormatSetupState.needsServiceSetup.title, "Needs service setup")
        XCTAssertEqual(MagicFormatSetupState.ready.title, "Ready")

        XCTAssertTrue(MagicFormatSetupState.off.detail.contains("Turn it on"))
        XCTAssertTrue(MagicFormatSetupState.needsAPIKey.detail.contains("API key"))
        XCTAssertTrue(MagicFormatSetupState.needsServiceSetup.detail.contains("service setup"))
        XCTAssertTrue(MagicFormatSetupState.ready.detail.contains("ready"))

        XCTAssertEqual(MagicFormatSetupState.off.icon, "pause.circle")
        XCTAssertEqual(MagicFormatSetupState.needsAPIKey.icon, "exclamationmark.circle")
        XCTAssertEqual(MagicFormatSetupState.needsServiceSetup.icon, "exclamationmark.circle")
        XCTAssertEqual(MagicFormatSetupState.ready.icon, "checkmark.circle.fill")

        XCTAssertEqual(MagicFormatSetupState.off.color, MainWindowPalette.secondaryText)
        XCTAssertEqual(MagicFormatSetupState.needsAPIKey.color, .orange)
        XCTAssertEqual(MagicFormatSetupState.needsServiceSetup.color, .orange)
        XCTAssertEqual(MagicFormatSetupState.ready.color, .green)
    }

    func testMagicFormatSetupTestResultSeverityColors() {
        XCTAssertEqual(MagicFormatSetupTestResult.Severity.success.color, .green)
        XCTAssertEqual(MagicFormatSetupTestResult.Severity.error.color, .red)
    }

    func testASRModelBannerToneDisplayProperties() {
        XCTAssertEqual(ASRModelBannerState.Tone.info.color, .accentColor)
        XCTAssertEqual(ASRModelBannerState.Tone.error.color, .red)
        XCTAssertEqual(ASRModelBannerState.Tone.info.icon, "arrow.triangle.2.circlepath.circle.fill")
        XCTAssertEqual(ASRModelBannerState.Tone.error.icon, "exclamationmark.triangle.fill")
    }

    func testAppStateErrorDescription() {
        XCTAssertEqual(
            AppStateError.modelValidationFailed.errorDescription,
            "Model files are missing after extraction."
        )
    }

    func testAppVersionText() {
        let appState = makeTestAppState()
        XCTAssertTrue(appState.appVersionText.contains("0.0.1"))

        let unknownVersion = makeTestAppState(currentAppVersionProvider: { nil })
        XCTAssertEqual(unknownVersion.appVersionText, "Unknown")
    }

    // MARK: - Catalog helpers

    func testCatalogDerivedProperties() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)

        XCTAssertEqual(appState.asrModelCatalog.map(\.id), modelManager.catalog.map(\.id))
        XCTAssertFalse(appState.availableASRModelEntries.map(\.id).contains(appState.selectedASRModelID))
        XCTAssertFalse(appState.hasAnyInstalledModel)
        XCTAssertFalse(appState.isModelInstalled)

        modelManager.installedModelIDs = [.parakeetV3]
        XCTAssertTrue(appState.hasAnyInstalledModel)
    }

    // MARK: - Model status value / color / icon

    func testModelStatusValueBranches() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = appState.selectedASRModelID
        appState.downloadProgress = 0.5
        XCTAssertEqual(appState.modelStatusValue, "Downloading 50%")

        appState.activeASRModelOperationID = .moonshineBase
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusValue, "Current")
        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelStatusValue, "Installed")
        modelManager.installedModelIDs = []
        XCTAssertEqual(appState.modelStatusValue, "Missing")

        modelManager.installedModelIDs = [.parakeetV3]
        appState.phase = .loading
        appState.activeASRModelOperationID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusValue, "Loading")
        modelManager.installedModelIDs = []
        XCTAssertEqual(appState.modelStatusValue, "Validating")
        appState.activeASRModelOperationID = .moonshineBase
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusValue, "Current")
        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelStatusValue, "Missing")

        modelManager.installedModelIDs = [.parakeetV3]
        appState.activeASRModelOperationID = nil
        appState.phase = .ready
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusValue, "Current")
        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelStatusValue, "Installed")

        appState.phase = .error
        appState.lastFailedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusValue, "Download failed")
        appState.lastFailedASRModelID = .moonshineBase
        XCTAssertEqual(appState.modelStatusValue, "Installed")

        appState.phase = .needsModel
        XCTAssertEqual(appState.modelStatusValue, "Missing")
    }

    func testModelStatusColorBranches() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.phase = .ready
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusColor, .green)
        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelStatusColor, .orange)

        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusColor, .accentColor)
        appState.activeASRModelOperationID = .moonshineBase
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusColor, .green)
        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelStatusColor, .orange)

        appState.phase = .error
        appState.lastFailedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusColor, .red)
        appState.lastFailedASRModelID = nil
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusColor, .green)
        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelStatusColor, .orange)

        appState.phase = .needsModel
        XCTAssertEqual(appState.modelStatusColor, .orange)
    }

    func testModelStatusIconBranches() {
        let appState = makeTestAppState()

        appState.phase = .ready
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusIcon, "checkmark.circle.fill")
        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelStatusIcon, "exclamationmark.triangle.fill")

        appState.phase = .loading
        appState.activeASRModelOperationID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusIcon, "arrow.down.circle.fill")
        appState.activeASRModelOperationID = .moonshineBase
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusIcon, "checkmark.circle.fill")
        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelStatusIcon, "exclamationmark.triangle.fill")

        appState.phase = .error
        appState.lastFailedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelStatusIcon, "xmark.octagon.fill")
        appState.lastFailedASRModelID = nil
        XCTAssertEqual(appState.modelStatusIcon, "checkmark.circle.fill")

        appState.phase = .needsModel
        XCTAssertEqual(appState.modelStatusIcon, "exclamationmark.triangle.fill")
    }

    // MARK: - Primary action title / detail

    func testModelPrimaryActionTitleBranches() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.activeASRModelOperationID = appState.selectedASRModelID
        appState.phase = .loading
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Loading…")
        appState.phase = .downloadingModel
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Downloading…")

        appState.activeASRModelOperationID = nil
        appState.phase = .ready
        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Current")

        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Use Model")

        modelManager.installedModelIDs = []
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Download Model")
    }

    func testModelPrimaryActionDetailBranches() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.loadedASRModelID = appState.selectedASRModelID
        XCTAssertTrue(appState.modelPrimaryActionDetail.contains("Stored locally"))

        appState.loadedASRModelID = nil
        appState.activeASRModelOperationID = appState.selectedASRModelID
        XCTAssertTrue(appState.modelPrimaryActionDetail.contains("Keep Suniye open"))

        appState.activeASRModelOperationID = nil
        appState.lastFailedASRModelID = appState.selectedASRModelID
        appState.lastFailedASRModelError = "boom"
        XCTAssertTrue(appState.modelPrimaryActionDetail.contains("Last attempt failed"))

        appState.lastFailedASRModelID = nil
        appState.lastFailedASRModelError = nil
        XCTAssertTrue(appState.modelPrimaryActionDetail.contains("fully local"))
    }

    func testModelLocationAndSizeTexts() {
        let appState = makeTestAppState()
        XCTAssertTrue(appState.modelLocationText.contains("suniye-models"))
        XCTAssertFalse(appState.modelInstalledSizeText.isEmpty)
        XCTAssertTrue(appState.modelExpectedSizeText.hasPrefix("~"))
        XCTAssertGreaterThan(appState.modelExpectedByteCount, 0)

        let failingManager = CovDisplayFailingModelManager()
        let fallbackState = makeTestAppState(modelManager: failingManager)
        XCTAssertEqual(fallbackState.modelLocationText, "~/Library/Application Support/Suniye/models")
        XCTAssertEqual(fallbackState.asrModelLocationText(for: .parakeetV3), "~/Library/Application Support/Suniye/models")
    }

    // MARK: - Banner

    func testASRModelBannerBranches() {
        let appState = makeTestAppState()

        XCTAssertNil(appState.asrModelBanner)

        appState.activeASRModelOperationID = .parakeetV3
        appState.phase = .downloadingModel
        appState.downloadProgress = 0.25
        let downloading = appState.asrModelBanner
        XCTAssertEqual(downloading?.title, "Downloading Model")
        XCTAssertEqual(downloading?.tone, .info)
        XCTAssertEqual(downloading?.progress, 0.25)

        appState.phase = .loading
        let loading = appState.asrModelBanner
        XCTAssertEqual(loading?.title, "Loading Model")
        XCTAssertNil(loading?.progress)

        // An active operation in any other phase falls through to no banner.
        appState.phase = .ready
        XCTAssertNil(appState.asrModelBanner)

        appState.activeASRModelOperationID = nil

        appState.lastFailedASRModelID = .parakeetV3
        appState.lastFailedASRModelError = "download exploded"
        let failed = appState.asrModelBanner
        XCTAssertEqual(failed?.title, "Model Action Failed")
        XCTAssertEqual(failed?.tone, .error)
        XCTAssertTrue(failed?.detail.contains("download exploded") == true)

        appState.lastFailedASRModelID = nil
        appState.lastFailedASRModelError = nil
        appState.phase = .error
        appState.lastError = "runtime broke"
        let errored = appState.asrModelBanner
        XCTAssertEqual(errored?.title, "Model Unavailable")
        XCTAssertEqual(errored?.detail, "runtime broke")
    }

    // MARK: - Per-model status helpers

    func testASRModelStatusTextBranches() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.activeASRModelOperationID = .parakeetV3
        appState.phase = .downloadingModel
        XCTAssertEqual(appState.asrModelStatusText(for: .parakeetV3), "Downloading")

        appState.phase = .loading
        XCTAssertEqual(appState.asrModelStatusText(for: .parakeetV3), "Loading")

        // An active operation in any other phase falls through to the ladder.
        appState.phase = .ready
        XCTAssertEqual(appState.asrModelStatusText(for: .parakeetV3), "Installed")

        appState.activeASRModelOperationID = nil

        appState.loadedASRModelID = .parakeetV3
        XCTAssertEqual(appState.asrModelStatusText(for: .parakeetV3), "Current")

        appState.loadedASRModelID = nil
        appState.lastFailedASRModelID = .parakeetV3
        XCTAssertEqual(appState.asrModelStatusText(for: .parakeetV3), "Failed")

        appState.lastFailedASRModelID = nil
        XCTAssertEqual(appState.asrModelStatusText(for: .parakeetV3), "Installed")
        XCTAssertEqual(appState.asrModelStatusText(for: .moonshineBase), "Missing")
    }

    func testASRModelStatusColorBranches() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.activeASRModelOperationID = .parakeetV3
        XCTAssertEqual(appState.asrModelStatusColor(for: .parakeetV3), .accentColor)

        appState.activeASRModelOperationID = nil
        appState.loadedASRModelID = .parakeetV3
        XCTAssertEqual(appState.asrModelStatusColor(for: .parakeetV3), .green)

        appState.loadedASRModelID = nil
        appState.lastFailedASRModelID = .parakeetV3
        XCTAssertEqual(appState.asrModelStatusColor(for: .parakeetV3), .red)

        appState.lastFailedASRModelID = nil
        XCTAssertEqual(appState.asrModelStatusColor(for: .parakeetV3), MainWindowPalette.secondaryText)
        XCTAssertEqual(appState.asrModelStatusColor(for: .moonshineBase), .orange)
    }

    func testASRModelPrimaryActionTitleAndAvailabilityBranches() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.activeASRModelOperationID = .parakeetV3
        appState.phase = .loading
        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .parakeetV3), "Loading…")

        appState.phase = .downloadingModel
        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .parakeetV3), "Downloading…")
        // Operations are serialised: nothing else can start while one runs.
        XCTAssertFalse(appState.asrModelCanPerformPrimaryAction(for: .parakeetV3))
        XCTAssertFalse(appState.asrModelSecondaryActionsEnabled(for: .parakeetV3))
        XCTAssertFalse(appState.asrModelCanPerformPrimaryAction(for: .moonshineBase))

        appState.activeASRModelOperationID = nil
        appState.phase = .recording
        XCTAssertFalse(appState.asrModelCanPerformPrimaryAction(for: .moonshineBase))

        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3
        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .parakeetV3), "Current")
        XCTAssertFalse(appState.asrModelCanPerformPrimaryAction(for: .parakeetV3))
        XCTAssertTrue(appState.asrModelCanPerformPrimaryAction(for: .moonshineBase))

        appState.loadedASRModelID = nil
        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .parakeetV3), "Use Model")
        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .moonshineBase), "Download Model")
        XCTAssertTrue(appState.asrModelSecondaryActionsEnabled(for: .parakeetV3))
        XCTAssertFalse(appState.asrModelSecondaryActionsEnabled(for: .moonshineBase))
    }

    func testASRModelProgressLabelBranches() {
        let appState = makeTestAppState()

        XCTAssertNil(appState.asrModelProgressLabel(for: .parakeetV3))

        appState.activeASRModelOperationID = .parakeetV3
        appState.phase = .downloadingModel
        appState.downloadProgress = 0.5
        XCTAssertEqual(appState.asrModelProgressLabel(for: .parakeetV3), appState.modelDownloadProgressLabel)

        appState.phase = .loading
        XCTAssertEqual(appState.asrModelProgressLabel(for: .parakeetV3), "Preparing the local recognizer.")

        appState.phase = .ready
        XCTAssertNil(appState.asrModelProgressLabel(for: .parakeetV3))
    }

    func testASRModelInstalledSizeText() {
        let appState = makeTestAppState()
        XCTAssertFalse(appState.asrModelInstalledSizeText(for: .parakeetV3).isEmpty)
    }

    // MARK: - Operation status / progress labels

    func testModelOperationStatusTextBranches() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        XCTAssertEqual(appState.modelOperationStatusText, "")
        XCTAssertFalse(appState.isModelOperationInProgress)

        appState.activeASRModelOperationID = .parakeetV3
        appState.phase = .downloadingModel
        XCTAssertTrue(appState.modelOperationStatusText.hasPrefix("Downloading"))
        XCTAssertTrue(appState.isModelOperationInProgress)

        appState.phase = .loading
        modelManager.installedModelIDs = []
        XCTAssertTrue(appState.modelOperationStatusText.hasPrefix("Extracting and validating"))
        modelManager.installedModelIDs = [.parakeetV3]
        XCTAssertTrue(appState.modelOperationStatusText.hasPrefix("Loading"))

        appState.phase = .ready
        XCTAssertEqual(appState.modelOperationStatusText, "")
    }

    func testModelDownloadProgressLabelAndETA() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appState = makeTestAppState(nowProvider: { now })

        // Not downloading: label is empty, ETA falls back to the estimating text.
        XCTAssertEqual(appState.modelDownloadProgressLabel, "")
        XCTAssertEqual(appState.modelDownloadETAStatusText, "Estimating time remaining")

        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = appState.selectedASRModelID
        appState.downloadProgress = 0.5

        // Elapsed under a second: still estimating.
        appState.modelDownloadStartedAt = now.addingTimeInterval(-0.5)
        XCTAssertEqual(appState.modelDownloadETAStatusText, "Estimating time remaining")
        XCTAssertTrue(appState.modelDownloadProgressLabel.contains("Estimating time remaining"))

        // Normal minutes/seconds ETA.
        appState.modelDownloadStartedAt = now.addingTimeInterval(-100)
        XCTAssertTrue(appState.modelDownloadETAStatusText.hasPrefix("About"))
        XCTAssertTrue(appState.modelDownloadProgressLabel.contains("50% downloaded"))
        XCTAssertTrue(appState.modelDownloadProgressLabel.contains("About"))

        // Hour-scale ETA takes the hour/minute formatter branch.
        appState.modelDownloadStartedAt = now.addingTimeInterval(-3600)
        appState.downloadProgress = 0.4
        XCTAssertTrue(appState.modelDownloadETAStatusText.hasPrefix("About"))

        // Nearly done.
        appState.downloadProgress = 0.999
        appState.modelDownloadStartedAt = now.addingTimeInterval(-100)
        XCTAssertEqual(appState.modelDownloadETAStatusText, "Almost done")
    }

    // MARK: - Launch at login

    func testLaunchAtLoginDisplayProperties() {
        let appState = makeTestAppState()

        appState.launchAtLoginStatus = .disabled
        XCTAssertEqual(appState.launchAtLoginDetailText, "Launch at login is off.")
        XCTAssertFalse(appState.launchAtLoginEnabledForUI)

        appState.launchAtLoginStatus = .enabled
        XCTAssertTrue(appState.launchAtLoginEnabledForUI)
        XCTAssertTrue(appState.launchAtLoginDetailText.contains("automatically"))

        appState.launchAtLoginStatus = .unsupported("Not supported here")
        XCTAssertEqual(appState.launchAtLoginDetailText, "Not supported here")
        XCTAssertFalse(appState.launchAtLoginEnabledForUI)
    }
}

/// Model manager whose directory lookups throw, to exercise location fallbacks.
private final class CovDisplayFailingModelManager: ModelManagerProtocol {
    var catalog: [ASRModelCatalogEntry] = ASRModelCatalog.entries
    var fallbackOrder: [ASRModelID] = ASRModelCatalog.fallbackOrder

    func modelsRootDirectoryURL() throws -> URL {
        throw FakeError(message: "no root")
    }

    func modelDirectoryURL(for modelID: ASRModelID) throws -> URL {
        throw FakeError(message: "no directory")
    }

    func isInstalled(_ modelID: ASRModelID) -> Bool {
        false
    }

    func installedModels() -> [ASRModelID] {
        []
    }

    func makeRecognizerConfig(for modelID: ASRModelID) throws -> RecognizerConfig {
        throw FakeError(message: "no config")
    }

    func downloadAndExtractModel(_ modelID: ASRModelID, progress: @escaping @Sendable (Double) -> Void) async throws {
        throw FakeError(message: "no download")
    }

    func expectedDownloadSizeBytes(for modelID: ASRModelID) -> Int64 {
        0
    }

    func installedByteCount(for modelID: ASRModelID) -> Int64 {
        0
    }

    func deleteModel(_ modelID: ASRModelID) throws {
        throw FakeError(message: "no delete")
    }
}
