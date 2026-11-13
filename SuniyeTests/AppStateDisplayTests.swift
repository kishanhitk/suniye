import SwiftUI
import XCTest
@testable import Suniye

@MainActor
final class AppStateDisplayTests: XCTestCase {
    func testAppVersionText() {
        let appState = makeTestAppState()
        XCTAssertEqual(appState.appVersionText, "v0.0.1 (1)")

        let unknownVersion = makeTestAppState(currentAppVersionProvider: { nil })
        XCTAssertEqual(unknownVersion.appVersionText, "Unknown")
    }

    func testAvailableModelEntriesExcludeTheSelectedModel() {
        let appState = makeTestAppState()

        let availableIDs = appState.availableASRModelEntries.map(\.id)

        XCTAssertFalse(availableIDs.contains(appState.selectedASRModelID))
        XCTAssertEqual(availableIDs.count, appState.asrModelCatalog.count - 1)
    }

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
        appState.phase = .downloadingModel
        // Operations are serialised: nothing else can start while one runs.
        XCTAssertFalse(appState.asrModelCanPerformPrimaryAction(for: .parakeetV3))
        XCTAssertFalse(appState.asrModelSecondaryActionsEnabled(for: .parakeetV3))
        XCTAssertFalse(appState.asrModelCanPerformPrimaryAction(for: .moonshineBase))

        appState.activeASRModelOperationID = nil
        appState.phase = .recording
        XCTAssertFalse(appState.asrModelCanPerformPrimaryAction(for: .moonshineBase))

        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3
        XCTAssertFalse(appState.asrModelCanPerformPrimaryAction(for: .parakeetV3))
        XCTAssertTrue(appState.asrModelCanPerformPrimaryAction(for: .moonshineBase))

        appState.loadedASRModelID = nil
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

    func testModelDownloadProgressLabelWaitsOneSecondBeforeETA() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appState = makeTestAppState(nowProvider: { now })

        XCTAssertEqual(appState.modelDownloadProgressLabel, "")

        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = appState.selectedASRModelID
        appState.downloadProgress = 0.5

        appState.modelDownloadStartedAt = now.addingTimeInterval(-0.5)
        XCTAssertTrue(appState.modelDownloadProgressLabel.hasSuffix("\nEstimating time remaining"))

        appState.modelDownloadStartedAt = now.addingTimeInterval(-100)
        XCTAssertTrue(appState.modelDownloadProgressLabel.hasPrefix("50% downloaded"))
        XCTAssertTrue(appState.modelDownloadProgressLabel.contains("\nAbout"))
    }

    func testLaunchAtLoginDisplayProperties() {
        let appState = makeTestAppState()

        appState.launchAtLoginStatus = .disabled
        XCTAssertFalse(appState.launchAtLoginEnabledForUI)

        appState.launchAtLoginStatus = .enabled
        XCTAssertTrue(appState.launchAtLoginEnabledForUI)

        appState.launchAtLoginStatus = .requiresApproval
        XCTAssertTrue(appState.launchAtLoginEnabledForUI)

        appState.launchAtLoginStatus = .unsupported("Not supported here")
        XCTAssertFalse(appState.launchAtLoginEnabledForUI)
    }

    func testModelDownloadDerivedUIStateWhileDownloading() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let now = Date(timeIntervalSince1970: 600)
        let appState = makeTestAppState(
            modelManager: modelManager,
            nowProvider: { now }
        )
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .parakeetV3
        appState.downloadProgress = 0.25
        appState.modelDownloadStartedAt = Date(timeIntervalSince1970: 540)

        XCTAssertEqual(appState.modelStatusValue, "Downloading 25%")
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Downloading…")
        XCTAssertEqual(appState.modelDownloadProgressLabel, "25% downloaded • 170 MB of ~680 MB\nAbout 3m left")
    }

    func testCurrentModelStaysCurrentWhileAnotherModelDownloads() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.senseVoice]
        let appState = makeTestAppState(modelManager: modelManager)
        appState.selectedASRModelID = .senseVoice
        appState.loadedASRModelID = .senseVoice
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .moonshineBase
        appState.downloadProgress = 0.2

        XCTAssertEqual(appState.modelStatusValue, "Current")
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Current")
    }

    func testModelDownloadProgressLabelShowsEstimatingBeforeETAIsKnown() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .parakeetV3
        appState.downloadProgress = 0

        XCTAssertEqual(appState.modelDownloadProgressLabel, "0% downloaded • Zero KB of ~680 MB\nEstimating time remaining")
    }

    func testModelDownloadDerivedUIStateAfterFailure() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .error
        appState.lastFailedASRModelID = .parakeetV3
        appState.lastFailedASRModelError = "network timeout"

        XCTAssertEqual(appState.modelStatusValue, "Download failed")
    }

    func testAttentionItemsIncludeRuntimeErrorAndMissingModel() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .error
        appState.lastError = "engine failure"

        let ids = appState.attentionItems.map(\.id)

        XCTAssertTrue(ids.contains("runtime-error"))
        XCTAssertTrue(ids.contains("model-missing"))
        XCTAssertEqual(
            appState.attentionItems.first(where: { $0.id == "runtime-error" })?.detail,
            "engine failure"
        )
    }

    func testAttentionItemsIncludeAppleMagicFormatUnavailable() {
        let appState = makeTestAppState()
        appState.llmEnabled = true
        appState.llmProvider = .appleFoundationModels

        let items = appState.attentionItems

        XCTAssertTrue(items.map(\.id).contains("apple-magic-format-unavailable"))
        XCTAssertEqual(
            items.first(where: { $0.id == "mic-permission-missing" })?.fixTitle,
            "Grant Access"
        )
    }

    func testAttentionItemsExposeMicrophonePermissionFixAction() throws {
        let appState = makeTestAppState()
        appState.hasMicPermission = false

        let item = try XCTUnwrap(appState.attentionItems.first { $0.id == "mic-permission-missing" })
        XCTAssertEqual(item.fixAction, .requestMicrophonePermission)
        XCTAssertEqual(item.fixTitle, "Grant Access")
    }

    func testAttentionItemsExposeAccessibilityPermissionFixAction() throws {
        let appState = makeTestAppState()
        appState.hasAccessibilityPermission = false

        let item = try XCTUnwrap(appState.attentionItems.first { $0.id == "accessibility-permission-missing" })
        XCTAssertEqual(item.fixAction, .requestAccessibilityPermission)
        XCTAssertEqual(item.fixTitle, "Grant Access")
    }
}

