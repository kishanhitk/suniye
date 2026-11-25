import XCTest
@testable import Suniye

/// Restart to Update with Sparkle stubbed: an update never cuts a dictation short.
@MainActor
final class UpdateFlowTests: XCTestCase {
    func testRestartToUpdateWaitsUntilTheDictationIsDone() async throws {
        let app = try FlowApp(self)
        await app.launch()
        app.updates.isUpdateReadyToInstall = true
        app.updates.notifyStateChanged()

        await app.pressShortcut()
        XCTAssertFalse(app.appState.canRestartToUpdate)
        app.appState.restartToUpdate()
        XCTAssertEqual(app.updates.installUpdateAndRelaunchCallCount, 0, "a restart would lose the recording")

        app.stubEngine.transcribeResult = .success("Before the update.")
        await app.releaseShortcut()
        app.appState.restartToUpdate()

        XCTAssertEqual(app.focusedApp.text, "Before the update.")
        XCTAssertEqual(app.updates.installUpdateAndRelaunchCallCount, 1)
    }
}

/// Report a Problem: what leaves the Mac, and what is taken out first.
@MainActor
final class IssueReportFlowTests: XCTestCase {
    func testAReportIsSentWithTheSecretsTakenOut() async throws {
        let app = try FlowApp(self)
        await app.launch()
        app.stubEngine.transcribeResult = .failure(FakeError(
            message: "api_key=sk-secretsecretsecret at \(NSHomeDirectory())/Library/Application Support/Suniye"
        ))
        await app.pressShortcut()
        await app.releaseShortcut()
        let logFile = AppLogger.shared.logFileURL
        await waitUntil { ((try? String(contentsOf: logFile, encoding: .utf8)) ?? "").contains("transcription failed: api_key=") }
        var sent: (contentType: String, body: Data)?
        StubURLProtocol.handler = { request in
            sent = (request.value(forHTTPHeaderField: "Content-Type") ?? "", StubURLProtocol.requestBody(of: request) ?? Data())
            let answer = #"{"success":true,"reportId":"r-1","issueId":"i-1","issueIdentifier":"KIS-1","issueUrl":"https://linear.app/x"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(answer.utf8))
        }

        let report = app.appState.issueReport
        report.type = .textInsertion
        report.title = "Paste failed"
        report.description = "Dictation finished but nothing appeared in the focused app."
        await report.submit()

        XCTAssertEqual(report.status, .sent)
        let request = try XCTUnwrap(sent)
        let boundary = try XCTUnwrap(request.contentType.components(separatedBy: "boundary=").last)
        let payload = String(decoding: try Self.part("payload", of: request.body, boundary: boundary), as: UTF8.self)
        XCTAssertTrue(payload.contains("Paste failed"))
        XCTAssertTrue(payload.contains("api_key=[REDACTED]"), "the last error is sent redacted")
        XCTAssertFalse(payload.contains("sk-secretsecretsecret"))
        XCTAssertFalse(payload.contains(NSHomeDirectory()))

        let archive = app.root.appendingPathComponent("uploaded.zip")
        let extracted = app.root.appendingPathComponent("extracted", isDirectory: true)
        try Self.part("diagnostics", of: request.body, boundary: boundary).write(to: archive)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", archive.path, "-d", extracted.path]
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)
        let uploadedLog = try String(contentsOf: extracted.appendingPathComponent("app.log"), encoding: .utf8)
        XCTAssertTrue(uploadedLog.contains("transcription failed: api_key=[REDACTED]"))
        XCTAssertFalse(uploadedLog.contains("sk-secretsecretsecret"))
        XCTAssertFalse(uploadedLog.contains(NSHomeDirectory()))
    }

    /// The bytes of one form field of a multipart body.
    private static func part(_ name: String, of body: Data, boundary: String) throws -> Data {
        let header = try XCTUnwrap(body.range(of: Data("Content-Disposition: form-data; name=\"\(name)\"".utf8)))
        let start = try XCTUnwrap(body.range(of: Data("\r\n\r\n".utf8), in: header.upperBound ..< body.endIndex)).upperBound
        let end = try XCTUnwrap(body.range(of: Data("\r\n--\(boundary)".utf8), in: start ..< body.endIndex)).lowerBound
        return body.subdata(in: start ..< end)
    }
}
