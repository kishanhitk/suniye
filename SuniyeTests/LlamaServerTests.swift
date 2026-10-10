import XCTest
@testable import Suniye

final class LlamaServerTests: XCTestCase {
    // MARK: - Arguments

    func testArgumentsAppendLoopbackPortKeyAndQuietFlagsToTheLaunchArguments() {
        let launch = LlamaServerLaunch(
            executableURL: URL(fileURLWithPath: "/tmp/llama-server"),
            arguments: ["--model", "/tmp/model.gguf"],
            modelName: "Model"
        )

        let arguments = LlamaServer.arguments(for: launch, port: 51_234, apiKey: "local-key")

        XCTAssertEqual(arguments, [
            "--model", "/tmp/model.gguf",
            "--host", "127.0.0.1",
            "--port", "51234",
            "--api-key", "local-key",
            "--no-webui",
            "--log-disable",
        ])
    }

    // MARK: - Lifecycle

    func testServerReusesProcessUntilIdleShutdown() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let launch = try makeLaunch(helperURL: FakeLlamaServer.make(in: tempDir, logURL: logURL))
        let server = LlamaServer()

        let isWarmBeforeStart = await server.isWarm(for: launch)
        XCTAssertFalse(isWarmBeforeStart)
        _ = try await server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
        let isWarmAfterStart = await server.isWarm(for: launch)
        XCTAssertTrue(isWarmAfterStart)
        _ = try await server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)

        XCTAssertEqual(FakeLlamaServer.count(of: "start", at: logURL), 1)

        await server.scheduleIdleShutdown(after: 0.05)
        // Poll for the idle shutdown to complete rather than asserting after a fixed sleep —
        // the terminate + wait-for-exit can exceed a couple hundred ms under CI load.
        let becameCold = await waitUntil { await !server.isWarm(for: launch) }
        XCTAssertTrue(becameCold, "server should shut down after the idle timeout")
        _ = try await server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)

        XCTAssertEqual(FakeLlamaServer.count(of: "start", at: logURL), 2)
        await server.stop()
    }

    func testLoadAndIdleEvictionReportTheModelName() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let launch = try makeLaunch(helperURL: FakeLlamaServer.make(in: tempDir, logURL: logURL))
        let events = LockedRecorder<String>()
        let server = LlamaServer(
            onModelLoad: { model, loadMs in events.record("load \(model) \(loadMs >= 0)") },
            onKeepAliveEvicted: { model in events.record("evicted \(model)") }
        )

        _ = try await server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 0.05)
        let evicted = await waitUntil { events.values.count == 2 }

        XCTAssertTrue(evicted, "idle shutdown should report the eviction")
        XCTAssertEqual(events.values, ["load Fake Model true", "evicted Fake Model"])
        await server.stop()
    }

    func testDifferentLaunchReplacesTheRunningProcess() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let helperURL = try FakeLlamaServer.make(in: tempDir, logURL: logURL)
        let first = makeLaunch(helperURL: helperURL, modelArgument: "/tmp/first.gguf")
        let second = makeLaunch(helperURL: helperURL, modelArgument: "/tmp/second.gguf")
        let server = LlamaServer()

        _ = try await server.endpoint(for: first, startupTimeoutSeconds: 8, idleTimeoutSeconds: 0)
        _ = try await server.endpoint(for: second, startupTimeoutSeconds: 8, idleTimeoutSeconds: 0)

        let firstIsWarm = await server.isWarm(for: first)
        let secondIsWarm = await server.isWarm(for: second)
        XCTAssertFalse(firstIsWarm)
        XCTAssertTrue(secondIsWarm)
        XCTAssertEqual(FakeLlamaServer.count(of: "start", at: logURL), 2)
        XCTAssertEqual(FakeLlamaServer.count(of: "term", at: logURL), 1)
        await server.stop()
    }

    func testConcurrentColdStartsReuseOneStartup() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let launch = try makeLaunch(helperURL: FakeLlamaServer.make(in: tempDir, logURL: logURL, startupDelaySeconds: 0.25))
        let server = LlamaServer()

        async let firstEndpoint = server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
        async let secondEndpoint = server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
        let endpoints = try await (firstEndpoint, secondEndpoint)

        XCTAssertEqual(endpoints.0, endpoints.1)
        XCTAssertEqual(FakeLlamaServer.count(of: "start", at: logURL), 1)
        await server.stop()
    }

    func testStopCancelsSharedStartupWithoutRestarting() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let launch = try makeLaunch(helperURL: FakeLlamaServer.make(in: tempDir, logURL: logURL, startupDelaySeconds: 5))
        let server = LlamaServer()
        let startupTask = Task {
            try await server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
        }

        let didStart = await FakeLlamaServer.waitForCount(of: "start", toReach: 1, at: logURL)
        XCTAssertTrue(didStart)

        await server.stop()

        do {
            _ = try await startupTask.value
            XCTFail("Expected the in-flight startup to be canceled")
        } catch {
            XCTAssertEqual(FakeLlamaServer.count(of: "start", at: logURL), 1)
            XCTAssertTrue(FakeLlamaServer.logContents(at: logURL).contains("term"))
        }
    }

    func testStopWaitsForHelperProcessExit() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let launch = try makeLaunch(helperURL: FakeLlamaServer.make(in: tempDir, logURL: logURL, terminationDelaySeconds: 0.25))
        let server = LlamaServer()

        _ = try await server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)

        let start = Date()
        await server.stop()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.18)
        XCTAssertTrue(FakeLlamaServer.logContents(at: logURL).contains("term"))
    }

    func testScheduleIdleShutdownWithZeroTimeoutIsDisabled() async {
        let server = LlamaServer()

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
        let launch = makeLaunch(helperURL: helperURL)
        let server = LlamaServer()

        // Startup never becomes healthy; we only need the helper process spawned.
        let startupTask = Task {
            _ = try await server.endpoint(for: launch, startupTimeoutSeconds: 30, idleTimeoutSeconds: 30)
        }
        let started = await waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: markerURL.path) }
        XCTAssertTrue(started, "helper process never started")

        let start = Date()
        async let firstStop: Void = server.stop()
        async let secondStop: Void = server.stop()
        _ = await (firstStop, secondStop)
        let elapsed = Date().timeIntervalSince(start)

        // TERM is ignored, so the shutdown path must escalate to SIGKILL after
        // the shutdown timeout instead of hanging forever.
        XCTAssertGreaterThanOrEqual(elapsed, LlamaServer.shutdownTimeoutSeconds - 0.2)
        XCTAssertLessThan(elapsed, 15)

        startupTask.cancel()
        _ = try? await startupTask.value
    }

    // MARK: - Startup failures

    func testMissingExecutableFailsToLaunch() async throws {
        let tempDir = try makeTemporaryDirectory()
        let server = LlamaServer()

        do {
            _ = try await server.endpoint(
                for: makeLaunch(helperURL: tempDir.appendingPathComponent("missing-helper")),
                startupTimeoutSeconds: 5,
                idleTimeoutSeconds: 30
            )
            XCTFail("Expected launchFailed")
        } catch let error as LlamaServerError {
            XCTAssertEqual(error, .launchFailed)
        }
    }

    func testExitDuringStartupSurfacesStderrTail() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = try makeExecutableScript(
            in: tempDir,
            named: "crashing-helper",
            body: """
            echo "boom fatal error" 1>&2
            exit 3
            """
        )
        let server = LlamaServer()

        do {
            _ = try await server.endpoint(for: makeLaunch(helperURL: helperURL), startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
            XCTFail("Expected server exit error")
        } catch let error as LlamaServerError {
            XCTAssertEqual(error, .exited(reason: "server_exited_3_boom fatal error"))
        }
    }

    func testExitDuringStartupWithoutStderrReportsStatusOnly() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = try makeExecutableScript(in: tempDir, named: "silent-helper", body: "exit 7")
        let server = LlamaServer()

        do {
            _ = try await server.endpoint(for: makeLaunch(helperURL: helperURL), startupTimeoutSeconds: 8, idleTimeoutSeconds: 30)
            XCTFail("Expected server exit error")
        } catch let error as LlamaServerError {
            XCTAssertEqual(error, .exited(reason: "server_exited_7"))
        }
    }

    func testStartupTimeoutStopsUnhealthyProcess() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let launch = try makeLaunch(helperURL: FakeLlamaServer.make(in: tempDir, logURL: logURL, healthStatus: 503))
        let server = LlamaServer()

        do {
            // Long enough that the helper reliably boots and serves its (unhealthy) 503
            // before the timeout fires, even under CI load — the 503 guarantees the timeout.
            _ = try await server.endpoint(for: launch, startupTimeoutSeconds: 4, idleTimeoutSeconds: 30)
            XCTFail("Expected startup timeout")
        } catch let error as LlamaServerError {
            XCTAssertEqual(error, .startupTimedOut)
        }

        // The helper may still be cold-starting under load; wait for it to record its start
        // rather than asserting on a fixed sleep.
        let didStart = await FakeLlamaServer.waitForCount(of: "start", toReach: 1, at: logURL)
        XCTAssertTrue(didStart)
        await server.stop()
    }

    func testNonHTTPHealthResponseKeepsServerUnhealthyUntilTimeout() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = try makeExecutableScript(
            in: tempDir,
            named: "sleeping-helper",
            body: "while :; do sleep 0.1; done"
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NonHTTPResponseURLProtocol.self]
        let server = LlamaServer(healthSession: URLSession(configuration: config))

        do {
            _ = try await server.endpoint(for: makeLaunch(helperURL: helperURL), startupTimeoutSeconds: 0.8, idleTimeoutSeconds: 30)
            XCTFail("Expected startup timeout")
        } catch let error as LlamaServerError {
            XCTAssertEqual(error, .startupTimedOut)
        }

        await server.stop()
    }

    // MARK: - Children outliving the app

    func testTerminateAllStopsRunningChildren() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        let launch = try makeLaunch(helperURL: FakeLlamaServer.make(in: tempDir, logURL: logURL))
        let server = LlamaServer()
        _ = try await server.endpoint(for: launch, startupTimeoutSeconds: 8, idleTimeoutSeconds: 0)

        LlamaServerChildren.terminateAll()

        let stopped = await waitUntil { await !server.isWarm(for: launch) }
        XCTAssertTrue(stopped, "the helper should exit on SIGTERM")
        XCTAssertTrue(FakeLlamaServer.logContents(at: logURL).contains("term"))
        await server.stop()
    }

    func testTerminateOrphansStopsOnlyOrphanedCopiesOfTheHelper() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = tempDir.appendingPathComponent("llama-server")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: helperURL)
        // A platform binary copied off the system volume is killed at launch until re-signed.
        let codesign = try Process.run(URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--force", "--sign", "-", helperURL.path])
        codesign.waitUntilExit()
        XCTAssertEqual(codesign.terminationStatus, 0)

        // A shell that backgrounds the helper and exits leaves it parented to launchd,
        // which is where a crashed app's helper ends up.
        let spawner = Process()
        spawner.executableURL = URL(fileURLWithPath: "/bin/sh")
        spawner.arguments = ["-c", "\"$0\" 30 >/dev/null 2>&1 & echo $!", helperURL.path]
        let output = Pipe()
        spawner.standardOutput = output
        try spawner.run()
        let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        spawner.waitUntilExit()
        let orphanPID = try XCTUnwrap(pid_t(printed.trimmingCharacters(in: .whitespacesAndNewlines)))
        addTeardownBlock { _ = Darwin.kill(orphanPID, SIGKILL) }

        let child = Process()
        child.executableURL = helperURL
        child.arguments = ["30"]
        try child.run()
        addTeardownBlock { child.terminate() }

        let orphaned = await waitUntil { Self.parentProcessID(of: orphanPID) == 1 }
        XCTAssertTrue(orphaned, "the backgrounded helper should be re-parented to launchd")

        XCTAssertEqual(LlamaServerChildren.terminateOrphans(of: helperURL), 1)

        let orphanGone = await waitUntil { Darwin.kill(orphanPID, 0) != 0 }
        XCTAssertTrue(orphanGone, "the orphaned helper should exit")
        XCTAssertTrue(child.isRunning, "a helper this process still owns must survive")
    }

    // MARK: - Helpers

    private func makeLaunch(helperURL: URL, modelArgument: String = "/tmp/model.gguf") -> LlamaServerLaunch {
        LlamaServerLaunch(executableURL: helperURL, arguments: ["--model", modelArgument], modelName: "Fake Model")
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

    private func makeExecutableScript(in directory: URL, named name: String, body: String) throws -> URL {
        let scriptURL = directory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
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

    private static func parentProcessID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return pid_t(info.pbi_ppid)
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
