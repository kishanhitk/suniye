import XCTest
@testable import Suniye

final class LocalGemmaLlamaCppClientMoreTests: XCTestCase {
    // MARK: - Client-level runtime state

    func testIsRuntimeWarmIsFalseWhenRuntimeCannotResolve() async {
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs = []
        let client = LocalGemmaLlamaCppClient(
            locator: LocalGemmaRuntimeLocator(modelManager: localManager),
            server: LlamaServer(),
            session: .shared
        )

        let warm = await client.isRuntimeWarm()

        XCTAssertFalse(warm)
    }

    func testIsRuntimeWarmAsksServerWhenRuntimeResolves() async throws {
        let tempDir = try makeTemporaryDirectory()
        let helperURL = try makeExecutableScript(in: tempDir, named: "fake-helper", body: "exit 0")
        overrideHelperPath(helperURL)
        let client = makeClient(rootDirectory: tempDir)

        // Server never started, so a resolvable runtime is still cold.
        let warm = await client.isRuntimeWarm()

        XCTAssertFalse(warm)
    }

    func testStopRuntimeForwardsToServer() async {
        let client = LocalGemmaLlamaCppClient(
            locator: LocalGemmaRuntimeLocator(modelManager: StubLocalLLMModelManager()),
            server: LlamaServer(),
            session: .shared
        )

        // Nothing is running; stop must be a safe no-op that returns.
        await client.stopRuntime()
    }

    // MARK: - Generation against a helper

    func testGenerateUsesBearerAuthAgainstLocalServer() async throws {
        let tempDir = try makeTemporaryDirectory()
        let logURL = tempDir.appendingPathComponent("starts.log")
        overrideHelperPath(try FakeLlamaServer.make(in: tempDir, logURL: logURL))
        let server = LlamaServer()
        let client = makeClient(rootDirectory: tempDir, server: server)

        let output: ChatCompletionResult
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
            XCTFail("Expected fake llama-server to become reachable, got \(error). Helper log: \(FakeLlamaServer.logContents(at: logURL))")
            return
        }

        XCTAssertEqual(output.text, "OK")
        let isWarm = await client.isRuntimeWarm()
        XCTAssertTrue(isWarm)
        await server.stop()
    }

    func testGenerateReportsHelperFailuresAsPostProcessorErrors() async throws {
        let tempDir = try makeTemporaryDirectory()
        let notAProgram = tempDir.appendingPathComponent("not-a-program")
        try Data("not a program".utf8).write(to: notAProgram)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notAProgram.path)
        let cases: [(URL, LLMPostProcessorError)] = [
            (notAProgram, .provider("server_start_failed")),
            (try makeExecutableScript(in: tempDir, named: "exiting-helper", body: "exit 7"), .provider("server_exited_7")),
            (try makeExecutableScript(in: tempDir, named: "silent-helper", body: "while :; do sleep 0.1; done"), .timeout),
        ]

        for (helperURL, expected) in cases {
            overrideHelperPath(helperURL)
            let server = LlamaServer()
            let client = makeClient(rootDirectory: tempDir, server: server)

            do {
                _ = try await client.generate(
                    instructions: "Reply with OK.",
                    prompt: "Connection test.",
                    maxTokens: 8,
                    startupTimeoutSeconds: 0.8,
                    idleTimeoutSeconds: 600,
                    timeoutSeconds: 5
                )
                XCTFail("Expected \(expected) from \(helperURL.lastPathComponent)")
            } catch let error as LLMPostProcessorError {
                XCTAssertEqual(error.errorDescription, expected.errorDescription, helperURL.lastPathComponent)
            }
            await server.stop()
        }
    }

    // MARK: - Helpers

    private func makeClient(rootDirectory: URL, server: LlamaServer = LlamaServer()) -> LocalGemmaLlamaCppClient {
        let localManager = StubLocalLLMModelManager()
        localManager.rootDirectory = rootDirectory
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        return LocalGemmaLlamaCppClient(
            locator: LocalGemmaRuntimeLocator(modelManager: localManager),
            server: server,
            session: .shared
        )
    }

    private func overrideHelperPath(_ helperURL: URL) {
        let previousHelperPath = getenv("SUNIYE_LLAMA_SERVER_PATH").map { String(cString: $0) }
        setenv("SUNIYE_LLAMA_SERVER_PATH", helperURL.path, 1)
        addTeardownBlock {
            if let previousHelperPath {
                setenv("SUNIYE_LLAMA_SERVER_PATH", previousHelperPath, 1)
            } else {
                unsetenv("SUNIYE_LLAMA_SERVER_PATH")
            }
        }
    }

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
}
