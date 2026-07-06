import XCTest
@testable import Suniye

final class LocalGemmaLlamaServerTests: XCTestCase {
    func testClientGenerateUsesBearerAuthAgainstLocalServer() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let helperURL = try makeFakeLlamaServer(in: tempDir, logURL: logURL)
        let localManager = StubLocalLLMModelManager()
        localManager.rootDirectory = tempDir
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let server = LocalGemmaLlamaServer()
        let previousHelperPath = getenv("SUNIYE_LLAMA_SERVER_PATH").map { String(cString: $0) }
        setenv("SUNIYE_LLAMA_SERVER_PATH", helperURL.path, 1)
        addTeardownBlock {
            if let previousHelperPath {
                setenv("SUNIYE_LLAMA_SERVER_PATH", previousHelperPath, 1)
            } else {
                unsetenv("SUNIYE_LLAMA_SERVER_PATH")
            }
        }

        let client = LocalGemmaLlamaCppClient(
            locator: LocalGemmaRuntimeLocator(modelManager: localManager),
            server: server,
            session: .shared
        )

        let output: String
        do {
            output = try await client.generate(
                instructions: "Reply with OK.",
                prompt: "Connection test.",
                maxTokens: 8,
                startupTimeoutSeconds: 8,
                idleTimeoutSeconds: 600,
                timeoutSeconds: 5
            )
        } catch {
            await server.stop()
            XCTFail("Expected fake llama-server to become reachable, got \(error). Helper log: \(logContents(at: logURL))")
            return
        }

        XCTAssertEqual(output, "OK")
        await server.stop()
    }

    func testServerReusesRuntimeUntilIdleShutdown() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let helperURL = try makeFakeLlamaServer(in: tempDir, logURL: logURL)
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()

        let isWarmBeforeStart = await server.isWarm(for: runtime)
        XCTAssertFalse(isWarmBeforeStart)
        _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
        let isWarmAfterStart = await server.isWarm(for: runtime)
        XCTAssertTrue(isWarmAfterStart)
        _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)

        XCTAssertEqual(startCount(at: logURL), 1)

        await server.scheduleIdleShutdown(after: 0.05)
        // Poll for the idle shutdown to complete rather than asserting after a fixed sleep —
        // the terminate + wait-for-exit can exceed a couple hundred ms under CI load.
        let becameCold = await waitUntil { await !server.isWarm(for: runtime) }
        XCTAssertTrue(becameCold, "server should shut down after the idle timeout")
        _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)

        XCTAssertEqual(startCount(at: logURL), 2)
        await server.stop()
    }

    func testConcurrentColdStartsReuseOneStartup() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let helperURL = try makeFakeLlamaServer(
            in: tempDir,
            logURL: logURL,
            startupDelaySeconds: 0.25
        )
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()

        async let firstEndpoint = server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
        async let secondEndpoint = server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
        let endpoints = try await (firstEndpoint, secondEndpoint)

        XCTAssertEqual(endpoints.0, endpoints.1)
        XCTAssertEqual(startCount(at: logURL), 1)
        await server.stop()
    }

    func testStopCancelsSharedStartupWithoutRestarting() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let helperURL = try makeFakeLlamaServer(
            in: tempDir,
            logURL: logURL,
            startupDelaySeconds: 5
        )
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()
        let startupTask = Task {
            try await server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
        }

        let didStart = await waitForStartCount(1, at: logURL)
        XCTAssertTrue(didStart)

        await server.stop()

        do {
            _ = try await startupTask.value
            XCTFail("Expected the in-flight startup to be canceled")
        } catch {
            XCTAssertEqual(startCount(at: logURL), 1)
            XCTAssertTrue(logContents(at: logURL).contains("term"))
        }
    }

    func testServerStartupTimeoutStopsUnhealthyProcess() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let helperURL = try makeFakeLlamaServer(in: tempDir, logURL: logURL, healthStatus: 503)
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()

        do {
            // Long enough that the helper reliably boots and serves its (unhealthy) 503
            // before the timeout fires, even under CI load — the 503 guarantees the timeout.
            _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 4, idleTimeoutSeconds: 30)
            XCTFail("Expected startup timeout")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, LLMPostProcessorError.timeout.errorDescription)
        }

        // The helper may still be cold-starting under load; wait for it to record its start
        // rather than asserting on a fixed sleep.
        let didStart = await waitForStartCount(1, at: logURL)
        XCTAssertTrue(didStart)
        await server.stop()
    }

    func testStopWaitsForHelperProcessExit() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let helperURL = try makeFakeLlamaServer(
            in: tempDir,
            logURL: logURL,
            terminationDelaySeconds: 0.25
        )
        let runtime = LocalGemmaRuntime(
            serverExecutableURL: helperURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: tempDir.appendingPathComponent(LocalGemmaDefaults.modelFilename)
        )
        let server = LocalGemmaLlamaServer()

        _ = try await server.endpoint(for: runtime, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)

        let start = Date()
        await server.stop()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.18)
        XCTAssertTrue(logContents(at: logURL).contains("term"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-llama-server-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeFakeLlamaServer(
        in directory: URL,
        logURL: URL,
        healthStatus: Int = 200,
        startupDelaySeconds: Double = 0,
        terminationDelaySeconds: Double = 0
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent("fake-llama-server")
        let logPathLiteral = try jsonStringLiteral(logURL.path)
        let script = """
        #!/usr/bin/python3
        import json
        import signal
        import sys
        import time
        import traceback
        from http.server import BaseHTTPRequestHandler, HTTPServer

        log_path = \(logPathLiteral)
        try:
            port = int(sys.argv[sys.argv.index("--port") + 1])
            api_key = sys.argv[sys.argv.index("--api-key") + 1]
            health_status = \(healthStatus)
            startup_delay_seconds = \(startupDelaySeconds)
            termination_delay_seconds = \(terminationDelaySeconds)
        except Exception:
            with open(log_path, "a", encoding="utf-8") as log:
                log.write("argument_error\\n")
                log.write(traceback.format_exc())
            raise

        def handle_sigterm(signum, frame):
            with open(log_path, "a", encoding="utf-8") as log:
                log.write("term\\n")
            time.sleep(termination_delay_seconds)
            sys.exit(0)

        signal.signal(signal.SIGTERM, handle_sigterm)

        with open(log_path, "a", encoding="utf-8") as log:
            log.write("start\\n")

        time.sleep(startup_delay_seconds)

        class Handler(BaseHTTPRequestHandler):
            def _authorized(self):
                return self.headers.get("Authorization") == "Bearer " + api_key

            def do_GET(self):
                if self.path != "/health":
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(health_status if self._authorized() else 401)
                self.end_headers()
                self.wfile.write(b"ok")

            def do_POST(self):
                if self.path != "/v1/chat/completions":
                    self.send_response(404)
                    self.end_headers()
                    return
                _ = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                if not self._authorized():
                    self.send_response(401)
                    self.end_headers()
                    return
                body = json.dumps({"choices": [{"message": {"content": "OK"}}]}).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format, *args):
                pass

        HTTPServer(("127.0.0.1", port), Handler).serve_forever()
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
            .replacingOccurrences(of: "\\/", with: "/")
    }

    private func startCount(at url: URL) -> Int {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return 0
        }
        return contents
            .split(separator: "\n")
            .filter { $0 == "start" }
            .count
    }

    /// Polls `condition` until it holds or the timeout elapses. Replaces fixed-sleep-then-
    /// assert patterns that flake when process/termination timing slips under CI load.
    private func waitUntil(timeout: TimeInterval = 10, _ condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }

    private func waitForStartCount(_ expectedCount: Int, at url: URL) async -> Bool {
        // Generous deadline: the fake Python helper's cold start can take several seconds
        // under CI parallel-test CPU load, well beyond a couple of seconds.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if startCount(at: url) >= expectedCount {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    private func logContents(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
