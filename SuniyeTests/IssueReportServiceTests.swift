import XCTest
@testable import Suniye

final class IssueReportServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockIssueReportURLProtocol.handler = nil
    }

    func testAppLoggerUsesIsolatedPathUnderTests() {
        XCTAssertTrue(AppLogger.shared.logFileURL.path.contains("SuniyeTests-"))
        XCTAssertFalse(AppLogger.shared.logFileURL.path.contains("Application Support/Suniye/logs"))
    }

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

    func testUploadServiceSendsMultipartAndDecodesSuccess() async throws {
        let endpointURL = URL(string: "https://suniye.test/api/issue-reports")!
        let diagnosticsURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try Data([0x50, 0x4B]).write(to: diagnosticsURL)
        defer { try? FileManager.default.removeItem(at: diagnosticsURL) }

        var capturedRequest: URLRequest?
        var capturedBody: Data?
        MockIssueReportURLProtocol.handler = { request in
            capturedRequest = request
            capturedBody = MockIssueReportURLProtocol.requestBodyData(from: request)
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
        MockIssueReportURLProtocol.handler = { _ in
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
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockIssueReportURLProtocol.self]
        return URLSession(configuration: config)
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

private final class MockIssueReportURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "suniye.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
