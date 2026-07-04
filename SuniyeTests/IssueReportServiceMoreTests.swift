import Foundation
import XCTest
@testable import Suniye

final class IssueReportServiceMoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MoreMockIssueReportURLProtocol.handler = nil
    }

    // MARK: - IssueReportType

    func testIssueReportTypeIdentityAndTitles() {
        let expectedTitles: [IssueReportType: String] = [
            .dictation: "Dictation",
            .hotkey: "Hotkey",
            .transcription: "Transcription",
            .textInsertion: "Text Insertion",
            .magicFormat: "Magic Format",
            .modelDownload: "Model Download",
            .permissions: "Permissions",
            .update: "Updates",
            .other: "Other",
        ]

        XCTAssertEqual(Set(IssueReportType.allCases), Set(expectedTitles.keys))
        for type in IssueReportType.allCases {
            XCTAssertEqual(type.id, type.rawValue)
            XCTAssertEqual(type.title, expectedTitles[type])
        }
    }

    // MARK: - IssueReportError

    func testErrorDescriptionsCoverAllCases() {
        XCTAssertEqual(
            IssueReportError.missingEndpoint.errorDescription,
            "Issue reporting endpoint is not configured."
        )
        XCTAssertEqual(
            IssueReportError.invalidResponse.errorDescription,
            "Issue reporting server returned an invalid response."
        )
        XCTAssertEqual(IssueReportError.serverMessage("boom").errorDescription, "boom")
        XCTAssertEqual(
            IssueReportError.httpStatus(503).errorDescription,
            "Issue reporting server returned HTTP 503."
        )
        XCTAssertEqual(IssueReportError.fileIO("disk full").errorDescription, "disk full")
        XCTAssertEqual(
            IssueReportError.zipFailed("bad zip").errorDescription,
            "Could not create diagnostics archive: bad zip"
        )
        XCTAssertEqual(IssueReportError.invalidInput("too short").errorDescription, "too short")
    }

    // MARK: - DiagnosticBundleService

    func testBundleSucceedsWithMissingLogFileByWritingEmptyLog() async throws {
        let service = DiagnosticBundleService()
        let missingLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-more-missing-\(UUID().uuidString).log")

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

    func testBundleThrowsZipFailedWhenArchiveDestinationIsInvalid() async throws {
        let service = DiagnosticBundleService(fileManager: SplitTemporaryDirectoryFileManager())

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

    // MARK: - IssueReportUploadService

    func testSubmitThrowsMissingEndpointWhenBundleHasNoEndpointConfigured() async throws {
        let bundle = try makeBundle(info: [
            "CFBundleIdentifier": "dev.suniye.tests.more.report.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL",
        ])
        let service = IssueReportUploadService(session: makeSession(), bundle: bundle)

        do {
            _ = try await service.submit(payload: makePayload(), diagnosticsURL: nil)
            XCTFail("Expected missingEndpoint error")
        } catch let error as IssueReportError {
            XCTAssertEqual(error, .missingEndpoint)
        }
    }

    func testSubmitMapsTransportFailureToServerMessage() async {
        MoreMockIssueReportURLProtocol.handler = { _ in
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
        MoreMockIssueReportURLProtocol.handler = { _ in
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
        MoreMockIssueReportURLProtocol.handler = { _ in
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
            .appendingPathComponent("suniye-more-missing-\(UUID().uuidString).zip")

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

    // MARK: - Helpers

    private static let endpointURL = URL(string: "https://suniye-more.test/api/issue-reports")!

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MoreMockIssueReportURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeLogFile() throws -> URL {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-more-log-\(UUID().uuidString).log")
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

    private func makeBundle(info: [String: Any]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuniyeIssueReportMoreTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleURL)
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private func makePayload() -> IssueReportPayload {
        IssueReportPayload(
            schemaVersion: 1,
            reportId: "suniye-more-test-report",
            issueType: .other,
            title: "Something went wrong",
            description: "Details about the problem.",
            contactEmail: nil,
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
                updateStatus: nil
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
}

// MARK: - Test doubles

/// Pretends directory creation succeeded without creating anything, so the
/// first staged file write fails.
private final class NoopCreateDirectoryFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        // Intentionally left blank.
    }
}

/// Creates the staging directory but plants a directory named "app.log"
/// inside it, so writing the redacted log fails.
private final class LogBlockingFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
        if url.lastPathComponent.hasPrefix("suniye-diagnostics-") {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("app.log", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }
}

/// Returns the real temporary directory for the staging area (first call) and
/// a nonexistent directory for the archive destination (second call), which
/// makes /usr/bin/zip exit nonzero.
private final class SplitTemporaryDirectoryFileManager: FileManager, @unchecked Sendable {
    private let missingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("suniye-more-missing-zip-\(UUID().uuidString)", isDirectory: true)
    private var temporaryDirectoryCalls = 0
    private let lock = NSLock()

    override var temporaryDirectory: URL {
        lock.lock()
        defer { lock.unlock() }
        temporaryDirectoryCalls += 1
        return temporaryDirectoryCalls == 1 ? FileManager.default.temporaryDirectory : missingDirectory
    }
}

private final class MoreMockIssueReportURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "suniye-more.test"
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
