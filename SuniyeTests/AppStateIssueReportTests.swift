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
        appState.issueReportType = .textInsertion
        appState.issueReportTitle = "Paste failed"
        appState.issueReportDescription = "Dictation completed but nothing appeared in the focused app."
        appState.issueReportContactEmail = "user@example.com"
        appState.lastError = "Failed with api_key=sk-secretsecretsecret in \(NSHomeDirectory())/Library/Application Support/Suniye"

        await appState.submitIssueReport()

        guard case let .sent(identifier, url) = appState.issueReportStatus else {
            XCTFail("Expected sent status")
            return
        }
        XCTAssertEqual(identifier, "KIS-128")
        XCTAssertEqual(url?.absoluteString, "https://linear.app/kishan/issue/KIS-128/report")
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
    }

    func testSubmitIssueReportCanOmitDiagnostics() async {
        let diagnosticService = StubDiagnosticBundleService()
        let uploadService = StubIssueReportUploadService()
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            issueReportUploadService: uploadService
        )
        appState.issueReportTitle = "Hotkey failed"
        appState.issueReportDescription = "The configured hotkey did not start recording."
        appState.issueReportIncludesDiagnostics = false

        await appState.submitIssueReport()

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

        await appState.submitIssueReport()

        guard case let .failed(message) = appState.issueReportStatus else {
            XCTFail("Expected failed status")
            return
        }
        XCTAssertEqual(message, "Add a short title for the issue.")
        XCTAssertEqual(diagnosticService.requests.count, 0)
        XCTAssertEqual(uploadService.submissions.count, 0)
    }

    func testIssueReportDraftRequirementMessagesExplainDisabledSubmit() {
        let appState = makeTestAppState()

        XCTAssertFalse(appState.canSubmitIssueReport)
        XCTAssertEqual(appState.issueReportTitleRequirementMessage, "Add 3 more characters to the title.")
        XCTAssertEqual(appState.issueReportDescriptionRequirementMessage, "Add 10 more characters to the description.")
        XCTAssertEqual(appState.issueReportSubmitRequirementMessage, "Add 3 more characters to the title.")

        appState.issueReportTitle = "Bug"
        XCTAssertNil(appState.issueReportTitleRequirementMessage)
        XCTAssertEqual(appState.issueReportSubmitRequirementMessage, "Add 10 more characters to the description.")

        appState.issueReportDescription = "Crashes now"
        XCTAssertNil(appState.issueReportDescriptionRequirementMessage)
        XCTAssertNil(appState.issueReportSubmitRequirementMessage)
        XCTAssertTrue(appState.canSubmitIssueReport)

        appState.issueReportContactEmail = "not-an-email"
        XCTAssertEqual(appState.issueReportSubmitRequirementMessage, "Enter a valid email address or leave it blank.")
        XCTAssertFalse(appState.canSubmitIssueReport)
    }

    func testSubmitIssueReportIgnoresReentryWhileBusy() async {
        let diagnosticService = StubDiagnosticBundleService()
        let uploadService = StubIssueReportUploadService()
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            issueReportUploadService: uploadService
        )
        appState.issueReportTitle = "Hotkey failed"
        appState.issueReportDescription = "The configured hotkey did not start recording."
        appState.issueReportStatus = .sending

        await appState.submitIssueReport()

        XCTAssertEqual(appState.issueReportStatus, .sending)
        XCTAssertEqual(diagnosticService.requests.count, 0)
        XCTAssertEqual(uploadService.submissions.count, 0)
    }

    func testSubmitIssueReportValidatesEmail() async {
        let uploadService = StubIssueReportUploadService()
        let appState = makeTestAppState(issueReportUploadService: uploadService)
        appState.issueReportTitle = "Model failed"
        appState.issueReportDescription = "The model download failed during extraction."
        appState.issueReportContactEmail = "not-an-email"

        await appState.submitIssueReport()

        guard case let .failed(message) = appState.issueReportStatus else {
            XCTFail("Expected failed status")
            return
        }
        XCTAssertEqual(message, "Enter a valid email address or leave it blank.")
        XCTAssertEqual(uploadService.submissions.count, 0)
    }

    func testReviewIssueReportDiagnosticsRemovesTemporaryArchiveAfterOpening() async throws {
        let diagnosticsURL = try makeTemporaryDiagnosticsArchive()
        let diagnosticService = StubDiagnosticBundleService(result: .success(diagnosticsURL))
        var openedURL: URL?
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            fileOpener: { url in
                openedURL = url
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                return true
            }
        )

        await appState.reviewIssueReportDiagnostics()

        XCTAssertEqual(openedURL, diagnosticsURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertEqual(appState.issueReportStatus, .idle)
        XCTAssertEqual(appState.issueReportDiagnosticsMessage, "Diagnostics opened for review.")
    }

    func testReviewIssueReportDiagnosticsRemovesTemporaryArchiveWhenOpenFails() async throws {
        let diagnosticsURL = try makeTemporaryDiagnosticsArchive()
        let diagnosticService = StubDiagnosticBundleService(result: .success(diagnosticsURL))
        let appState = makeTestAppState(
            diagnosticBundleService: diagnosticService,
            fileOpener: { _ in false }
        )

        await appState.reviewIssueReportDiagnostics()

        XCTAssertFalse(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertEqual(appState.issueReportStatus, .failed("Could not open diagnostics."))
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

        await appState.exportIssueReportDiagnostics()

        XCTAssertEqual(requestedDefaultName, diagnosticsURL.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertEqual(appState.issueReportStatus, .idle)
        XCTAssertNil(appState.issueReportDiagnosticsMessage)
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

        await appState.exportIssueReportDiagnostics()

        XCTAssertFalse(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data([5, 6, 7]))
        XCTAssertEqual(appState.issueReportStatus, .idle)
        XCTAssertEqual(appState.issueReportDiagnosticsMessage, "Diagnostics exported.")
    }

    private func makeTemporaryDiagnosticsArchive(_ bytes: [UInt8] = [1, 2, 3]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID().uuidString).zip")
        try Data(bytes).write(to: url)
        return url
    }
}
