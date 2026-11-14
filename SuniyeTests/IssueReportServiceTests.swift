import XCTest
@testable import Suniye

final class IssueReportServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
    }

    private static let endpointURL = URL(string: "https://suniye.test/api/issue-reports")!

    func testRedactorRemovesSecretsAndSensitivePayloads() {
        let redactor = DiagnosticRedactor(homeDirectory: "/Users/kishan")
        let raw = """
        path=/Users/kishan/Library/Application Support/Suniye/logs/app.log
        email=user@example.com
        Authorization: Bearer secret-token-123
        api_key=sk-secretsecretsecret
        https://example.com?token=abc123&x=1
        transcript: this should not leave the machine
        clipboard=secret clipboard
        device_uid=private-device-id
        device_name=Private Microphone
        device-uid=private-hyphen-device-id
        device-name=Private Hyphen Microphone
        {"device_uid":"private-json-device-id","device-name":"Private JSON Microphone"}
        """

        let redacted = redactor.redact(raw)

        XCTAssertFalse(redacted.contains("/Users/kishan"))
        XCTAssertFalse(redacted.contains("user@example.com"))
        XCTAssertFalse(redacted.contains("secret-token-123"))
        XCTAssertFalse(redacted.contains("sk-secretsecretsecret"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("this should not leave"))
        XCTAssertFalse(redacted.contains("secret clipboard"))
        XCTAssertFalse(redacted.contains("private-device-id"))
        XCTAssertFalse(redacted.contains("Private Microphone"))
        XCTAssertFalse(redacted.contains("private-hyphen-device-id"))
        XCTAssertFalse(redacted.contains("Private Hyphen Microphone"))
        XCTAssertFalse(redacted.contains("private-json-device-id"))
        XCTAssertFalse(redacted.contains("Private JSON Microphone"))
        XCTAssertTrue(redacted.contains("~/Library/Application Support/Suniye/logs/app.log"))
        XCTAssertTrue(redacted.contains("[REDACTED_EMAIL]"))
    }

    func testDiagnosticBundleContainsSanitizedManifestAndLogs() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let logURL = tempRoot.appendingPathComponent("app.log")
        let rotatedLogURL = tempRoot.appendingPathComponent("app.log.1")
        try """
        2026-05-22 [INFO] path=/Users/kishan/Library/Application Support/Suniye
        2026-05-22 [INFO] api_key=sk-secretsecretsecret
        """.write(to: logURL, atomically: true, encoding: .utf8)
        try "user@example.com token=secret-token".write(to: rotatedLogURL, atomically: true, encoding: .utf8)

        let service = DiagnosticBundleService(
            fileManager: .default,
            redactor: DiagnosticRedactor(homeDirectory: "/Users/kishan")
        )

        let archiveURL = try await service.makeBundle(
            request: DiagnosticBundleRequest(
                payload: makePayload(),
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                logFileURL: logURL,
                rotatedLogFileURL: rotatedLogURL
            )
        )
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let extractedURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try unzip(archiveURL, to: extractedURL)

        let manifest = try String(contentsOf: extractedURL.appendingPathComponent("manifest.json"), encoding: .utf8)
        let appLog = try String(contentsOf: extractedURL.appendingPathComponent("app.log"), encoding: .utf8)
        let rotatedLog = try String(contentsOf: extractedURL.appendingPathComponent("app.log.1"), encoding: .utf8)
        let redactionReport = try String(contentsOf: extractedURL.appendingPathComponent("redaction-report.json"), encoding: .utf8)

        XCTAssertTrue(manifest.contains("\"reportId\" : \"suniye-test-report\""))
        XCTAssertTrue(manifest.contains("Diagnostics exclude audio"))
        XCTAssertTrue(redactionReport.contains("\"redacted\" : true"))
        XCTAssertFalse(appLog.contains("/Users/kishan"))
        XCTAssertFalse(appLog.contains("sk-secretsecretsecret"))
        XCTAssertTrue(appLog.contains("~/Library/Application Support/Suniye"))
        XCTAssertFalse(rotatedLog.contains("user@example.com"))
        XCTAssertFalse(rotatedLog.contains("secret-token"))
    }

    func testBundleSucceedsWithMissingLogFileByWritingEmptyLog() async throws {
        let service = DiagnosticBundleService()
        let missingLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-missing-\(UUID().uuidString).log")

        let archiveURL = try await service.makeBundle(request: makeRequest(logFileURL: missingLog))
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testBundleThrowsFileIOWhenStagingDirectoryCannotBeWritten() async throws {
        let service = DiagnosticBundleService(fileManager: NoopCreateDirectoryFileManager())

        do {
            _ = try await service.makeBundle(request: makeRequest(logFileURL: makeLogFile()))
            XCTFail("Expected fileIO error")
        } catch let error as IssueReportError {
            guard case .fileIO = error else {
                return XCTFail("Expected fileIO, got \(error)")
            }
        }
    }

    func testBundleThrowsFileIOWhenRedactedLogCannotBeWritten() async throws {
        let service = DiagnosticBundleService(fileManager: LogBlockingFileManager())

        do {
            _ = try await service.makeBundle(request: makeRequest(logFileURL: makeLogFile()))
            XCTFail("Expected fileIO error")
        } catch let error as IssueReportError {
            guard case .fileIO = error else {
                return XCTFail("Expected fileIO, got \(error)")
            }
        }
    }

    func testBundleThrowsZipFailedWhenArchiveCannotBeWritten() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-zip-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let service = DiagnosticBundleService(fileManager: ReadOnlyAfterStagingFileManager(root: root))

        do {
            _ = try await service.makeBundle(request: makeRequest(logFileURL: makeLogFile()))
            XCTFail("Expected zipFailed error")
        } catch let error as IssueReportError {
            guard case let .zipFailed(message) = error else {
                return XCTFail("Expected zipFailed, got \(error)")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testUploadServiceSendsMultipartAndDecodesSuccess() async throws {
        let endpointURL = URL(string: "https://suniye.test/api/issue-reports")!
        let diagnosticsURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try Data([0x50, 0x4B]).write(to: diagnosticsURL)
        defer { try? FileManager.default.removeItem(at: diagnosticsURL) }

        var capturedRequest: URLRequest?
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            capturedBody = StubURLProtocol.requestBody(of: request)
            let response = HTTPURLResponse(url: endpointURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
            {
              "success": true,
              "reportId": "suniye-test-report",
              "issueId": "issue-id",
              "issueIdentifier": "KIS-128",
              "issueUrl": "https://linear.app/kishan/issue/KIS-128/report"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let service = IssueReportUploadService(session: makeSession(), endpointURL: endpointURL)
        let response = try await service.submit(payload: makePayload(), diagnosticsURL: diagnosticsURL)

        XCTAssertEqual(response.reportId, "suniye-test-report")
        XCTAssertEqual(response.issueIdentifier, "KIS-128")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "User-Agent"), "Suniye/IssueReporter")
        let body = try XCTUnwrap(capturedBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("name=\"payload\""))
        XCTAssertTrue(body.contains("name=\"diagnostics\"; filename=\"\(diagnosticsURL.lastPathComponent)\""))
        XCTAssertTrue(body.contains("\"reportId\":\"suniye-test-report\""))
    }

    func testUploadServiceSurfacesServerErrorMessage() async {
        let endpointURL = URL(string: "https://suniye.test/api/issue-reports")!
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(url: endpointURL, statusCode: 400, httpVersion: nil, headerFields: nil)!
            let data = """
            {
              "success": false,
              "error": {
                "code": "invalid_payload",
                "message": "Title must be 3-160 characters."
              }
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let service = IssueReportUploadService(session: makeSession(), endpointURL: endpointURL)

        do {
            _ = try await service.submit(payload: makePayload(), diagnosticsURL: nil)
            XCTFail("Expected server error")
        } catch let error as IssueReportError {
            XCTAssertEqual(error, .serverMessage("Title must be 3-160 characters."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSubmitThrowsMissingEndpointWhenBundleHasNoEndpointConfigured() async throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuniyeIssueReportTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleURL)
        }
        let info: [String: Any] = [
            "CFBundleIdentifier": "dev.suniye.tests.report.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))
        let service = IssueReportUploadService(session: makeSession(), bundle: try XCTUnwrap(Bundle(url: bundleURL)))

        do {
            _ = try await service.submit(payload: makePayload(), diagnosticsURL: nil)
            XCTFail("Expected missingEndpoint error")
        } catch let error as IssueReportError {
            XCTAssertEqual(error, .missingEndpoint)
        }
    }

    func testSubmitMapsTransportFailureToServerMessage() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = IssueReportUploadService(session: makeSession(), endpointURL: Self.endpointURL)

        do {
            _ = try await service.submit(payload: makePayload(), diagnosticsURL: nil)
            XCTFail("Expected serverMessage error")
        } catch let error as IssueReportError {
            XCTAssertEqual(error, .serverMessage("Could not reach issue reporting server."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSubmitThrowsInvalidResponseForNonHTTPResponse() async {
        StubURLProtocol.handler = { _ in
            let response = URLResponse(
                url: Self.endpointURL,
                mimeType: "application/json",
                expectedContentLength: 2,
                textEncodingName: nil
            )
            return (response, Data("{}".utf8))
        }
        let service = IssueReportUploadService(session: makeSession(), endpointURL: Self.endpointURL)

        do {
            _ = try await service.submit(payload: makePayload(), diagnosticsURL: nil)
            XCTFail("Expected invalidResponse error")
        } catch let error as IssueReportError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSubmitThrowsInvalidResponseWhenSuccessEnvelopeIsIncomplete() async {
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(url: Self.endpointURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success": false}"#.utf8))
        }
        let service = IssueReportUploadService(session: makeSession(), endpointURL: Self.endpointURL)

        do {
            _ = try await service.submit(payload: makePayload(), diagnosticsURL: nil)
            XCTFail("Expected invalidResponse error")
        } catch let error as IssueReportError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSubmitThrowsFileIOWhenDiagnosticsFileIsMissing() async {
        let service = IssueReportUploadService(session: makeSession(), endpointURL: Self.endpointURL)
        let missingDiagnostics = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-missing-\(UUID().uuidString).zip")

        do {
            _ = try await service.submit(payload: makePayload(), diagnosticsURL: missingDiagnostics)
            XCTFail("Expected fileIO error")
        } catch let error as IssueReportError {
            guard case .fileIO = error else {
                return XCTFail("Expected fileIO, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeLogFile() throws -> URL {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-log-\(UUID().uuidString).log")
        try "2026-07-04 [INFO] hello".write(to: logURL, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: logURL)
        }
        return logURL
    }

    private func makeRequest(logFileURL: URL) -> DiagnosticBundleRequest {
        DiagnosticBundleRequest(
            payload: makePayload(),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            logFileURL: logFileURL,
            rotatedLogFileURL: nil
        )
    }

    private func makePayload() -> IssueReportPayload {
        IssueReportPayload(
            schemaVersion: 1,
            reportId: "suniye-test-report",
            issueType: .dictation,
            title: "Dictation failed",
            description: "Recording completes but no text is pasted.",
            contactEmail: "user@example.com",
            includeDiagnostics: true,
            app: .init(
                version: "v0.0.8",
                build: "8",
                macOSVersion: "15.5",
                architecture: "arm64"
            ),
            state: .init(
                phase: "ready",
                lastError: nil,
                updateStatus: "upToDate"
            ),
            permissions: .init(
                microphone: true,
                accessibility: false
            ),
            model: .init(
                selectedModelId: "parakeetV3",
                selectedModelName: "Parakeet v3",
                selectedModelInstalled: true,
                installedModelIds: ["parakeetV3"]
            ),
            settings: .init(
                autoSubmitEnabled: false,
                echoCancellationEnabled: true,
                soundFeedbackEnabled: true,
                hideFloatingIndicatorWhenIdle: false,
                llmEnabled: false,
                llmHasAPIKey: false
            )
        )
    }

    private func makeSession() -> URLSession {
        URLSession(configuration: StubURLProtocol.sessionConfiguration())
    }

    private func unzip(_ archiveURL: URL, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archiveURL.path, "-d", destinationURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

/// Pretends directory creation succeeded without creating anything, so the
/// first staged file write fails.
private final class NoopCreateDirectoryFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {}
}

/// Plants a directory named "app.log" in each directory it creates, so the
/// redacted log cannot be written there.
private final class LogBlockingFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("app.log", isDirectory: true),
            withIntermediateDirectories: true
        )
    }
}

/// Uses `root` as the temporary directory and makes it read-only once the
/// staging directory exists, so the staged files can be written but the
/// archive next to them cannot.
private final class ReadOnlyAfterStagingFileManager: FileManager, @unchecked Sendable {
    private let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    override var temporaryDirectory: URL {
        root
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
    }
}
