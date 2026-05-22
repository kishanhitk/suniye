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
}
