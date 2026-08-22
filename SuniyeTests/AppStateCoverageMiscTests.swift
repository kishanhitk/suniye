import AppKit
import XCTest
@testable import Suniye

/// Coverage tests for issue-report window lifecycle residuals, input device
/// display fallbacks, system settings deep links, attention items, and
/// pasteboard actions.
@MainActor
final class AppStateCoverageMiscTests: XCTestCase {
    // MARK: - Issue report window lifecycle

    func testPrepareIssueReportWindowPresentationClearsMessageOnly() {
        let appState = makeTestAppState()
        appState.issueReportDiagnosticsMessage = "old message"
        appState.issueReportTitle = "My bug"

        appState.prepareIssueReportWindowPresentation()

        XCTAssertNil(appState.issueReportDiagnosticsMessage)
        XCTAssertEqual(appState.issueReportTitle, "My bug")
    }

    func testWindowClosedDuringSubmissionResetsFailedDraftOnNextClose() {
        let appState = makeTestAppState()
        appState.issueReportTitle = "My bug"
        appState.issueReportStatus = .preparing

        // Closing mid-submission arms the deferred reset.
        appState.issueReportWindowDidClose()

        appState.issueReportStatus = .failed("upload broke")
        appState.issueReportWindowDidClose()

        XCTAssertEqual(appState.issueReportStatus, .idle)
        XCTAssertEqual(appState.issueReportTitle, "")
    }

    func testPreparePresentationDisarmsDeferredResetWhenSubmissionRecovered() {
        let appState = makeTestAppState()
        appState.issueReportTitle = "My bug"
        appState.issueReportStatus = .sending
        appState.issueReportWindowDidClose()

        // Submission finished idle in the meantime; reopening must disarm the flag.
        appState.issueReportStatus = .idle
        appState.prepareIssueReportWindowPresentation()

        appState.issueReportStatus = .failed("later failure")
        appState.issueReportWindowDidClose()

        // Without the armed flag a failed close keeps the draft.
        XCTAssertEqual(appState.issueReportStatus, .failed("later failure"))
        XCTAssertEqual(appState.issueReportTitle, "My bug")
    }

    // MARK: - Issue report submission failures

    func testSubmitIssueReportUploadFailureUsesPlainErrorDescription() async {
        let upload = StubIssueReportUploadService(
            result: .failure(NSError(
                domain: "SuniyeTests",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "plain failure"]
            ))
        )
        let appState = makeTestAppState(issueReportUploadService: upload)
        appState.issueReportTitle = "Bug title"
        appState.issueReportDescription = "A long enough description."
        appState.issueReportIncludesDiagnostics = false

        await appState.submitIssueReport()

        XCTAssertEqual(appState.issueReportStatus, .failed("plain failure"))
    }

    func testSubmitIssueReportRejectsShortDescription() async {
        let appState = makeTestAppState()
        appState.issueReportTitle = "Bug title"
        appState.issueReportDescription = "short"

        await appState.submitIssueReport()

        XCTAssertEqual(
            appState.issueReportStatus,
            .failed("Describe what happened in a little more detail.")
        )
    }

    func testReviewIssueReportDiagnosticsFailureShowsLocalizedError() async {
        let diagnostics = StubDiagnosticBundleService(result: .failure(FakeError(message: "bundle broke")))
        let appState = makeTestAppState(diagnosticBundleService: diagnostics)

        await appState.reviewIssueReportDiagnostics()

        XCTAssertEqual(appState.issueReportStatus, .failed("bundle broke"))
    }

    func testExportIssueReportDiagnosticsOverwritesExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cov-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("diagnostics.zip")
        try Data("fresh diagnostics".utf8).write(to: sourceURL)
        let destinationURL = directory.appendingPathComponent("existing.zip")
        try Data("stale".utf8).write(to: destinationURL)

        let diagnostics = StubDiagnosticBundleService(result: .success(sourceURL))
        let appState = makeTestAppState(
            diagnosticBundleService: diagnostics,
            issueReportDiagnosticsDestinationPicker: { _ in destinationURL }
        )

        await appState.exportIssueReportDiagnostics()

        XCTAssertEqual(appState.issueReportStatus, .idle)
        XCTAssertEqual(appState.issueReportDiagnosticsMessage, "Diagnostics exported.")
        XCTAssertEqual(
            try String(contentsOf: destinationURL, encoding: .utf8),
            "fresh diagnostics"
        )
    }

    func testExportIssueReportDiagnosticsFailureShowsError() async {
        let diagnostics = StubDiagnosticBundleService(result: .failure(FakeError(message: "no bundle")))
        let appState = makeTestAppState(diagnosticBundleService: diagnostics)

        await appState.exportIssueReportDiagnostics()

        XCTAssertEqual(appState.issueReportStatus, .failed("no bundle"))
    }

    // MARK: - System settings deep links

    func testOpenSystemSettingsFailureSetsLastError() {
        var attemptedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: { url in
            attemptedURLs.append(url)
            return false
        })

        appState.openMicrophonePrivacySettings()

        XCTAssertEqual(attemptedURLs.count, 2)
        XCTAssertEqual(appState.lastError, "Unable to open System Settings.")
    }

    func testOpenAppleIntelligenceSettingsOpensFirstCandidate() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: { url in
            openedURLs.append(url)
            return true
        })

        appState.openAppleIntelligenceSettings()

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(
            openedURLs.first?.absoluteString,
            "x-apple.systempreferences:com.apple.Siri-Settings.extension"
        )
        XCTAssertNil(appState.lastError)
    }

    // MARK: - Input devices

    func testDeviceListRefreshUpdatesPersistedDeviceName() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(id: "usb-1", name: "New Name", isDefault: false, transport: .usb),
        ]
        let settingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: "usb-1",
                preferredInputDeviceName: "Old Name"
            )
        )

        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            generalSettingsStore: settingsStore
        )
        appState.refreshInputDevices()

        XCTAssertEqual(appState.selectedInputDeviceName, "New Name")
        XCTAssertEqual(settingsStore.latest.preferredInputDeviceName, "New Name")
    }

    func testUseRecommendedInputDeviceNoOpWithoutCandidates() {
        let appState = makeTestAppState()

        appState.useRecommendedInputDevice()

        XCTAssertNil(appState.selectedInputDeviceID)
    }

    func testSelectedInputDeviceNameFallbacks() {
        // Route snapshot present, no selection: uses the effective route name.
        let routed = makeTestAppState()
        XCTAssertEqual(routed.selectedInputDeviceName, "System Microphone")

        // Selection points at a vanished device with no remembered name.
        routed.selectedInputDeviceID = "ghost-device"
        routed.availableInputDevices = []
        XCTAssertEqual(routed.selectedInputDeviceName, "Selected Microphone")

        // No route: fall back to the default device, then to "System Default".
        let unrouted = StubAudioCaptureService()
        unrouted.routeSnapshotError = FakeError(message: "no route")
        unrouted.availableDevices = [
            AudioInputDevice(id: "mac-mic", name: "Mac Microphone", isDefault: true, transport: .builtIn),
        ]
        let fallbackState = makeTestAppState(audioCaptureService: unrouted)
        XCTAssertEqual(fallbackState.selectedInputDeviceName, "Mac Microphone")

        fallbackState.availableInputDevices = []
        XCTAssertEqual(fallbackState.selectedInputDeviceName, "System Default")
        XCTAssertEqual(fallbackState.effectiveInputDeviceStatusText, "No microphone is available")
    }

    func testAudioRouteWarningTextEchoCancellationMismatch() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.route = AudioRouteSnapshot(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: "mac-mic",
            effectiveInputName: "Mac Microphone",
            inputTransport: .builtIn,
            outputTransport: .builtIn,
            inputSampleRate: 16_000,
            inputChannelCount: 1,
            requestedEchoCancellation: true,
            effectiveEchoCancellation: false,
            backend: .inputOnlyHAL,
            fallbackReason: nil
        )
        let appState = makeTestAppState(audioCaptureService: audioCapture)

        XCTAssertEqual(
            appState.audioRouteWarningText,
            "Echo cancellation is unavailable for the current audio route."
        )
    }

    func testAudioRouteWarningTextNilForHealthyRoute() {
        let appState = makeTestAppState()
        XCTAssertNil(appState.audioRouteWarningText)
    }

    func testRecommendedInputDeviceOrderingPrefersDefaultThenBuiltInThenName() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(id: "usb-z", name: "Zeta USB", isDefault: false, transport: .usb),
            AudioInputDevice(id: "built-b", name: "Beta Built-in", isDefault: false, transport: .builtIn),
            AudioInputDevice(id: "built-a", name: "Alpha Built-in", isDefault: false, transport: .builtIn),
        ]
        audioCapture.route = AudioRouteSnapshot(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: "bt-current",
            effectiveInputName: "BT Headset",
            inputTransport: .bluetooth,
            outputTransport: .bluetooth,
            inputSampleRate: 16_000,
            inputChannelCount: 1,
            requestedEchoCancellation: false,
            effectiveEchoCancellation: false,
            backend: .inputOnlyHAL,
            fallbackReason: nil
        )
        let appState = makeTestAppState(audioCaptureService: audioCapture)

        // Built-in beats USB; ties break alphabetically.
        XCTAssertEqual(appState.recommendedInputDevice?.id, "built-a")

        audioCapture.availableDevices.append(
            AudioInputDevice(id: "usb-default", name: "Default USB", isDefault: true, transport: .usb)
        )
        appState.refreshInputDevices()

        // A default device wins over everything else.
        XCTAssertEqual(appState.recommendedInputDevice?.id, "usb-default")
    }

    // MARK: - Attention items

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
        XCTAssertEqual(AttentionItemFixAction.requestMicrophonePermission.title, "Grant Access")
        XCTAssertEqual(
            items.first(where: { $0.id == "mic-permission-missing" })?.fixTitle,
            "Grant Access"
        )
    }

    // MARK: - Pasteboard

    func testCopyRecentResultWritesTextToPasteboard() {
        let appState = makeTestAppState()
        let result = RecentResult(
            id: UUID(),
            text: "copied dictation",
            createdAt: Date(),
            durationSeconds: 2,
            wasLLMPolished: false
        )

        appState.copyRecentResult(result)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "copied dictation")
    }
}
