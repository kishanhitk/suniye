import XCTest
@testable import Suniye

final class LocalGemmaLlamaCppClientMoreTests: XCTestCase {
    // MARK: - Client-level runtime state

    func testIsRuntimeWarmIsFalseWhenRuntimeCannotResolve() async {
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs = []
        let client = LocalGemmaLlamaCppClient(
            locator: LocalGemmaRuntimeLocator(modelManager: localManager),
            server: LocalGemmaLlamaServer(),
            session: .shared
        )

        let warm = await client.isRuntimeWarm()

        XCTAssertFalse(warm)
    }

    func testIsRuntimeWarmAsksServerWhenRuntimeResolves() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = try makeExecutableScript(in: tempDir, named: "fake-helper", body: "exit 0")
        let previousHelperPath = getenv("SUNIYE_LLAMA_SERVER_PATH").map { String(cString: $0) }
        setenv("SUNIYE_LLAMA_SERVER_PATH", helperURL.path, 1)
        addTeardownBlock {
            if let previousHelperPath {
                setenv("SUNIYE_LLAMA_SERVER_PATH", previousHelperPath, 1)
            } else {
                unsetenv("SUNIYE_LLAMA_SERVER_PATH")
            }
        }
        let localManager = StubLocalLLMModelManager()
        localManager.rootDirectory = tempDir
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let client = LocalGemmaLlamaCppClient(
            locator: LocalGemmaRuntimeLocator(modelManager: localManager),
            server: LocalGemmaLlamaServer(),
            session: .shared
        )

        // Server never started, so a resolvable runtime is still cold.
        let warm = await client.isRuntimeWarm()

        XCTAssertFalse(warm)
    }

    func testStopRuntimeForwardsToServer() async {
        let client = LocalGemmaLlamaCppClient(
            locator: LocalGemmaRuntimeLocator(modelManager: StubLocalLLMModelManager()),
            server: LocalGemmaLlamaServer(),
            session: .shared
        )

        // Nothing is running; stop must be a safe no-op that returns.
        await client.stopRuntime()
    }

    // MARK: - Server startup failures

    func testMissingServerExecutableFailsStartup() async throws {
        let tempDir = try makeTemporaryDirectory()
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: tempDir.appendingPathComponent("missing-helper"),
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()

        do {
            _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 5, idleTimeoutSeconds: 30)
            XCTFail("Expected server_start_failed")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.provider("server_start_failed").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerExitDuringStartupSurfacesStderrTail() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = try makeExecutableScript(
            in: tempDir,
            named: "crashing-helper",
            body: """
            echo "boom fatal error" 1>&2
            exit 3
            """
        )
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()

        do {
            _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
            XCTFail("Expected server exit error")
        } catch let error as LLMPostProcessorError {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains("server_exited_3"), "unexpected: \(description)")
            XCTAssertTrue(description.contains("boom fatal error"), "unexpected: \(description)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerExitDuringStartupWithoutStderrReportsStatusOnly() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = try makeExecutableScript(in: tempDir, named: "silent-helper", body: "exit 7")
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()

        do {
            _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
            XCTFail("Expected server exit error")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.provider("server_exited_7").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonHTTPHealthResponseKeepsServerUnhealthyUntilTimeout() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = try makeExecutableScript(
            in: tempDir,
            named: "sleeping-helper",
            body: "while :; do sleep 0.1; done"
        )
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NonHTTPResponseURLProtocol.self]
        let server = LocalGemmaLlamaServer(healthSession: URLSession(configuration: config))

        do {
            _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 0.8, idleTimeoutSeconds: 30)
            XCTFail("Expected startup timeout")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.timeout.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await server.stop()
    }

    // MARK: - Idle shutdown and stop

    func testScheduleIdleShutdownWithZeroTimeoutIsDisabled() async {
        let server = LocalGemmaLlamaServer()

        await server.scheduleIdleShutdown(after: 0)
        // No shutdown task exists; the actor stays responsive.
        await server.stop()
    }

    func testConcurrentStopsShareOneTerminationAndSIGKILLStubbornHelper() async throws {
        let tempDir = try makeTemporaryDirectory()
        let markerURL = tempDir.appendingPathComponent("started.marker")
        let helperURL = try makeExecutableScript(
            in: tempDir,
            named: "stubborn-helper",
            body: """
            trap '' TERM
            echo started >> "\(markerURL.path)"
            while :; do sleep 0.2; done
            """
        )
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()

        // Startup never becomes healthy; we only need the helper process spawned.
        let startupTask = Task {
            _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 30, idleTimeoutSeconds: 30)
        }
        let started = await waitForFile(at: markerURL, timeout: 5)
        XCTAssertTrue(started, "helper process never started")

        let start = Date()
        async let firstStop: Void = server.stop()
        async let secondStop: Void = server.stop()
        _ = await (firstStop, secondStop)
        let elapsed = Date().timeIntervalSince(start)

        // TERM is ignored, so the shutdown path must escalate to SIGKILL after
        // the shutdown timeout instead of hanging forever.
        XCTAssertGreaterThanOrEqual(elapsed, LocalGemmaDefaults.shutdownTimeoutSeconds - 0.2)
        XCTAssertLessThan(elapsed, 15)

        startupTask.cancel()
        _ = try? await startupTask.value
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-llama-client-more-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeExecutableScript(in directory: URL, named name: String, body: String) throws -> URL {
        let scriptURL = directory.appendingPathComponent(name)
        let script = "#!/bin/sh\n\(body)\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func waitForFile(at url: URL, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }
}

/// Responds to health probes with a bare (non-HTTP) URLResponse so the health
/// check's response-type guard is exercised.
private final class NonHTTPResponseURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = URLResponse(
            url: request.url!,
            mimeType: "text/plain",
            expectedContentLength: 2,
            textEncodingName: nil
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
