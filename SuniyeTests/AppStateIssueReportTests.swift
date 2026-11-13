import XCTest
@testable import Suniye

@MainActor
final class AppStateIssueReportTests: XCTestCase {
    func testSubmitIssueReportBuildsDiagnosticsAndUploadsPayload() async {
        let diagnosticsURL = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID().uuidString).zip")
        try? Data([1, 2, 3]).write(to: diagnosticsURL)
        defer { try? FileManager.default.removeItem(at: diagnosticsURL) }

        let diagnosticService = StubDiagnosticBundleService(result: .success(diagnosticsURL))
        let uploadService = StubIssueReportUploadService()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3]
        let appState = makeTestAppState(
            modelManager: modelManager,
            diagnosticBundleService: diagnosticService,
            issueReportUploadService: uploadService,
            currentAppVersionProvider: { AppVersion(marketing: SemVer(rawValue: "0.0.8")!, build: 8) },
            nowProvider: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = false
        appState.issueReport.type = .textInsertion
        appState.issueReport.title = "Paste failed"
        appState.issueReport.description = "Dictation completed but nothing appeared in the focused app."
        appState.issueReport.contactEmail = "user@example.com"
        appState.lastError = "Failed with api_key=sk-secretsecretsecret in \(NSHomeDirectory())/Library/Application Support/Suniye"

        await appState.issueReport.submit()

        guard case .sent = appState.issueReport.status else {
            XCTFail("Expected sent status")
            return
        }
        XCTAssertEqual(diagnosticService.requests.count, 1)
        XCTAssertEqual(uploadService.submissions.count, 1)
        XCTAssertEqual(uploadService.submissions.first?.diagnosticsURL, diagnosticsURL)
        XCTAssertEqual(uploadService.submissions.first?.payload.issueType, .textInsertion)
        XCTAssertEqual(uploadService.submissions.first?.payload.title, "Paste failed")
        XCTAssertEqual(uploadService.submissions.first?.payload.contactEmail, "user@example.com")
        XCTAssertEqual(
            uploadService.submissions.first?.payload.state.lastError,
            "Failed with api_key=[REDACTED] in ~/Library/Application Support/Suniye"
        )
        XCTAssertEqual(uploadService.submissions.first?.payload.permissions.accessibility, false)
        XCTAssertEqual(uploadService.submissions.first?.payload.app.version, "v0.0.8 (8)")
        XCTAssertEqual(uploadService.submissions.first?.payload.state.updateStatus, "sparkle-stable")
    }

    func testSubmitIssueReportCanOmitDiagnostics() async {
        let diagnosticService = StubDiagnosticBundleService()
        let uploadService = StubIssueReportUploadService()
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            issueReportUploadService: uploadService
        )
        appState.issueReport.title = "Hotkey failed"
        appState.issueReport.description = "The configured hotkey did not start recording."
        appState.issueReport.includesDiagnostics = false

        await appState.issueReport.submit()

        XCTAssertEqual(diagnosticService.requests.count, 0)
        XCTAssertEqual(uploadService.submissions.count, 1)
        XCTAssertNil(uploadService.submissions.first?.diagnosticsURL)
        XCTAssertEqual(uploadService.submissions.first?.payload.includeDiagnostics, false)
    }

    func testSubmitIssueReportValidatesDraftBeforeUpload() async {
        let diagnosticService = StubDiagnosticBundleService()
        let uploadService = StubIssueReportUploadService()
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            issueReportUploadService: uploadService
        )

        await appState.issueReport.submit()

        guard case let .failed(message) = appState.issueReport.status else {
            XCTFail("Expected failed status")
            return
        }
        XCTAssertEqual(message, "Add a short title for the issue.")
        XCTAssertEqual(diagnosticService.requests.count, 0)
        XCTAssertEqual(uploadService.submissions.count, 0)
    }

    func testIssueReportDraftRequirementMessagesExplainDisabledSubmit() {
        let appState = makeTestAppState()

        XCTAssertFalse(appState.issueReport.canSubmit)
        XCTAssertEqual(appState.issueReport.titleRequirementMessage, "Add 3 more characters to the title.")
        XCTAssertEqual(appState.issueReport.descriptionRequirementMessage, "Add 10 more characters to the description.")
        XCTAssertEqual(appState.issueReport.submitRequirementMessage, "Add 3 more characters to the title.")

        appState.issueReport.title = "Bug"
        XCTAssertNil(appState.issueReport.titleRequirementMessage)
        XCTAssertEqual(appState.issueReport.submitRequirementMessage, "Add 10 more characters to the description.")

        appState.issueReport.description = "Crashes now"
        XCTAssertNil(appState.issueReport.descriptionRequirementMessage)
        XCTAssertNil(appState.issueReport.submitRequirementMessage)
        XCTAssertTrue(appState.issueReport.canSubmit)

        appState.issueReport.contactEmail = "not-an-email"
        XCTAssertEqual(appState.issueReport.submitRequirementMessage, "Enter a valid email address or leave it blank.")
        XCTAssertFalse(appState.issueReport.canSubmit)
    }

    func testSubmitIssueReportIgnoresReentryWhileBusy() async {
        let diagnosticService = StubDiagnosticBundleService()
        let uploadService = StubIssueReportUploadService()
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            issueReportUploadService: uploadService
        )
        appState.issueReport.title = "Hotkey failed"
        appState.issueReport.description = "The configured hotkey did not start recording."
        appState.issueReport.status = .sending

        await appState.issueReport.submit()

        XCTAssertEqual(appState.issueReport.status, .sending)
        XCTAssertEqual(diagnosticService.requests.count, 0)
        XCTAssertEqual(uploadService.submissions.count, 0)
    }

    func testIssueReportWindowCloseWhileSendingResetsCompletedSubmissionOnNextPresentation() {
        let appState = makeTestAppState()
        appState.issueReport.type = .hotkey
        appState.issueReport.title = "Hotkey failed"
        appState.issueReport.description = "The configured hotkey did not start recording."
        appState.issueReport.contactEmail = "user@example.com"
        appState.issueReport.includesDiagnostics = false
        appState.issueReport.diagnosticsMessage = "Diagnostics opened for review."
        appState.issueReport.status = .sending

        appState.issueReport.windowDidClose()
        appState.issueReport.windowWillOpen()

        XCTAssertEqual(appState.issueReport.status, .sending)
        XCTAssertEqual(appState.issueReport.title, "Hotkey failed")
        XCTAssertNil(appState.issueReport.diagnosticsMessage)

        appState.issueReport.status = .sent
        appState.issueReport.diagnosticsMessage = "Diagnostics opened for review."

        appState.issueReport.windowWillOpen()

        XCTAssertEqual(appState.issueReport.status, .idle)
        XCTAssertEqual(appState.issueReport.type, .other)
        XCTAssertEqual(appState.issueReport.title, "")
        XCTAssertEqual(appState.issueReport.description, "")
        XCTAssertEqual(appState.issueReport.contactEmail, "")
        XCTAssertTrue(appState.issueReport.includesDiagnostics)
        XCTAssertNil(appState.issueReport.diagnosticsMessage)
    }

    func testIssueReportWindowCloseAfterSentResetsDraftImmediately() {
        let appState = makeTestAppState()
        appState.issueReport.title = "Paste failed"
        appState.issueReport.description = "Dictation completed but nothing appeared in the focused app."
        appState.issueReport.status = .sent

        appState.issueReport.windowDidClose()

        XCTAssertEqual(appState.issueReport.status, .idle)
        XCTAssertEqual(appState.issueReport.title, "")
        XCTAssertEqual(appState.issueReport.description, "")
    }

    func testSubmitIssueReportValidatesEmail() async {
        let uploadService = StubIssueReportUploadService()
        let appState = makeTestAppState(issueReportUploadService: uploadService)
        appState.issueReport.title = "Model failed"
        appState.issueReport.description = "The model download failed during extraction."
        appState.issueReport.contactEmail = "not-an-email"

        await appState.issueReport.submit()

        guard case let .failed(message) = appState.issueReport.status else {
            XCTFail("Expected failed status")
            return
        }
        XCTAssertEqual(message, "Enter a valid email address or leave it blank.")
        XCTAssertEqual(uploadService.submissions.count, 0)
    }

    func testReviewIssueReportDiagnosticsSchedulesTemporaryArchiveCleanupAfterOpening() async throws {
        let diagnosticsURL = try makeTemporaryDiagnosticsArchive()
        defer { try? FileManager.default.removeItem(at: diagnosticsURL) }
        let diagnosticService = StubDiagnosticBundleService(result: .success(diagnosticsURL))
        var openedURL: URL?
        var scheduledCleanupURL: URL?
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            fileOpener: { url in
                openedURL = url
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                return true
            },
            temporaryFileCleanupScheduler: { url in
                scheduledCleanupURL = url
            }
        )

        await appState.issueReport.reviewDiagnostics()

        XCTAssertEqual(openedURL, diagnosticsURL)
        XCTAssertEqual(scheduledCleanupURL, diagnosticsURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertEqual(appState.issueReport.status, .idle)
        XCTAssertEqual(appState.issueReport.diagnosticsMessage, "Diagnostics opened for review.")
    }

    func testReviewIssueReportDiagnosticsRemovesTemporaryArchiveWhenOpenFails() async throws {
        let diagnosticsURL = try makeTemporaryDiagnosticsArchive()
        let diagnosticService = StubDiagnosticBundleService(result: .success(diagnosticsURL))
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            fileOpener: { _ in false }
        )

        await appState.issueReport.reviewDiagnostics()

        XCTAssertFalse(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertEqual(appState.issueReport.status, .failed("Could not open diagnostics."))
    }

    func testExportIssueReportDiagnosticsRemovesTemporaryArchiveWhenCanceled() async throws {
        let diagnosticsURL = try makeTemporaryDiagnosticsArchive()
        let diagnosticService = StubDiagnosticBundleService(result: .success(diagnosticsURL))
        var requestedDefaultName: String?
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            issueReportDiagnosticsDestinationPicker: { defaultName in
                requestedDefaultName = defaultName
                return nil
            }
        )

        await appState.issueReport.exportDiagnostics()

        XCTAssertEqual(requestedDefaultName, diagnosticsURL.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertEqual(appState.issueReport.status, .idle)
        XCTAssertNil(appState.issueReport.diagnosticsMessage)
    }

    func testExportIssueReportDiagnosticsRemovesTemporaryArchiveAfterCopying() async throws {
        let diagnosticsURL = try makeTemporaryDiagnosticsArchive([5, 6, 7])
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-export-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let diagnosticService = StubDiagnosticBundleService(result: .success(diagnosticsURL))
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            issueReportDiagnosticsDestinationPicker: { _ in destinationURL }
        )

        await appState.issueReport.exportDiagnostics()

        XCTAssertFalse(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data([5, 6, 7]))
        XCTAssertEqual(appState.issueReport.status, .idle)
        XCTAssertEqual(appState.issueReport.diagnosticsMessage, "Diagnostics exported.")
    }

    private func makeTemporaryDiagnosticsArchive(_ bytes: [UInt8] = [1, 2, 3]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID().uuidString).zip")
        try Data(bytes).write(to: url)
        return url
    }

    func testPrepareIssueReportWindowPresentationClearsMessageOnly() {
        let appState = makeTestAppState()
        appState.issueReport.diagnosticsMessage = "old message"
        appState.issueReport.title = "My bug"

        appState.issueReport.windowWillOpen()

        XCTAssertNil(appState.issueReport.diagnosticsMessage)
        XCTAssertEqual(appState.issueReport.title, "My bug")
    }

    func testWindowClosedDuringSubmissionResetsFailedDraftOnNextClose() {
        let appState = makeTestAppState()
        appState.issueReport.title = "My bug"
        appState.issueReport.status = .preparing

        // Closing mid-submission arms the deferred reset.
        appState.issueReport.windowDidClose()

        appState.issueReport.status = .failed("upload broke")
        appState.issueReport.windowDidClose()

        XCTAssertEqual(appState.issueReport.status, .idle)
        XCTAssertEqual(appState.issueReport.title, "")
    }

    func testPreparePresentationDisarmsDeferredResetWhenSubmissionRecovered() {
        let appState = makeTestAppState()
        appState.issueReport.title = "My bug"
        appState.issueReport.status = .sending
        appState.issueReport.windowDidClose()

        // Submission finished idle in the meantime; reopening must disarm the flag.
        appState.issueReport.status = .idle
        appState.issueReport.windowWillOpen()

        appState.issueReport.status = .failed("later failure")
        appState.issueReport.windowDidClose()

        // Without the armed flag a failed close keeps the draft.
        XCTAssertEqual(appState.issueReport.status, .failed("later failure"))
        XCTAssertEqual(appState.issueReport.title, "My bug")
    }

    func testSubmitIssueReportUploadFailureUsesPlainErrorDescription() async {
        let upload = StubIssueReportUploadService(
            result: .failure(NSError(
                domain: "SuniyeTests",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "plain failure"]
            ))
        )
        let appState = makeTestAppState(issueReportUploadService: upload)
        appState.issueReport.title = "Bug title"
        appState.issueReport.description = "A long enough description."
        appState.issueReport.includesDiagnostics = false

        await appState.issueReport.submit()

        XCTAssertEqual(appState.issueReport.status, .failed("plain failure"))
    }

    func testSubmitIssueReportRejectsShortDescription() async {
        let appState = makeTestAppState()
        appState.issueReport.title = "Bug title"
        appState.issueReport.description = "short"

        await appState.issueReport.submit()

        XCTAssertEqual(
            appState.issueReport.status,
            .failed("Describe what happened in a little more detail.")
        )
    }

    func testReviewIssueReportDiagnosticsFailureShowsLocalizedError() async {
        let diagnostics = StubDiagnosticBundleService(result: .failure(FakeError(message: "bundle broke")))
        let appState = makeTestAppState(diagnosticBundleService: diagnostics)

        await appState.issueReport.reviewDiagnostics()

        XCTAssertEqual(appState.issueReport.status, .failed("bundle broke"))
    }

    func testExportIssueReportDiagnosticsOverwritesExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-export-\(UUID().uuidString)", isDirectory: true)
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

        await appState.issueReport.exportDiagnostics()

        XCTAssertEqual(appState.issueReport.status, .idle)
        XCTAssertEqual(appState.issueReport.diagnosticsMessage, "Diagnostics exported.")
        XCTAssertEqual(
            try String(contentsOf: destinationURL, encoding: .utf8),
            "fresh diagnostics"
        )
    }

    func testExportIssueReportDiagnosticsFailureShowsError() async {
        let diagnostics = StubDiagnosticBundleService(result: .failure(FakeError(message: "no bundle")))
        let appState = makeTestAppState(diagnosticBundleService: diagnostics)

        await appState.issueReport.exportDiagnostics()

        XCTAssertEqual(appState.issueReport.status, .failed("no bundle"))
    }
}
