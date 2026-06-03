import Foundation
import Darwin

final class LocalGemmaLlamaCppClient: LocalGemmaClient {
    private let locator: LocalGemmaRuntimeLocator
    private let server: LocalGemmaLlamaServer
    private let completionClient: ChatCompletionClient

    init(
        locator: LocalGemmaRuntimeLocator = LocalGemmaRuntimeLocator(),
        server: LocalGemmaLlamaServer? = nil,
        session: URLSession = .shared
    ) {
        self.locator = locator
        self.server = server ?? LocalGemmaLlamaServer(healthSession: session)
        self.completionClient = ChatCompletionClient(session: session)
    }

    var availability: LocalGemmaAvailability {
        switch locator.resolve() {
        case .success:
            return .available
        case let .failure(availability):
            return availability
        }
    }

    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int,
        startupTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> String {
        let runtime: LocalGemmaRuntime
        switch locator.resolve() {
        case let .success(resolved):
            runtime = resolved
        case let .failure(availability):
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        let endpoint = try await server.endpoint(
            for: runtime,
            startupTimeoutSeconds: startupTimeoutSeconds,
            idleTimeoutSeconds: LocalGemmaDefaults.idleTimeoutSeconds
        )
        defer {
            Task {
                await server.scheduleIdleShutdown(after: LocalGemmaDefaults.idleTimeoutSeconds)
            }
        }

        return try await completionClient.complete(
            endpointURL: endpoint.baseURL.appendingPathComponent("v1/chat/completions"),
            apiKey: endpoint.apiKey,
            payload: LocalGemmaCompletionRequestFactory.makePayload(
                instructions: instructions,
                prompt: prompt,
                maxTokens: maxTokens,
                modelName: runtime.model.displayName
            ),
            timeoutSeconds: timeoutSeconds
        )
    }

    func stopRuntime() async {
        await server.stop()
    }
}

struct LocalGemmaServerEndpoint: Equatable {
    let baseURL: URL
    let apiKey: String
}

enum LocalGemmaCompletionRequestFactory {
    static func makeRequest(
        endpoint: LocalGemmaServerEndpoint,
        instructions: String,
        prompt: String,
        maxTokens: Int,
        modelName: String,
        timeoutSeconds: Double
    ) throws -> URLRequest {
        try ChatCompletionRequestFactory.makeRequest(
            endpointURL: endpoint.baseURL.appendingPathComponent("v1/chat/completions"),
            apiKey: endpoint.apiKey,
            payload: makePayload(
                instructions: instructions,
                prompt: prompt,
                maxTokens: maxTokens,
                modelName: modelName
            ),
            timeoutSeconds: timeoutSeconds
        )
    }

    static func makePayload(instructions: String, prompt: String, maxTokens: Int, modelName: String) -> ChatCompletionPayload {
        let userContent = """
        \(instructions)

        \(prompt)
        """

        return ChatCompletionPayload(
            model: modelName,
            messages: [ChatCompletionMessage(role: "user", content: userContent)],
            temperature: 0,
            topK: 1,
            topP: 1,
            maxTokens: maxTokens,
            stream: false
        )
    }
}

actor LocalGemmaLlamaServer {
    private let healthSession: URLSession
    private var process: Process?
    private var runtime: LocalGemmaRuntime?
    private var endpoint: LocalGemmaServerEndpoint?
    private var idleShutdownTask: Task<Void, Never>?
    private var stoppingTask: Task<Void, Never>?

    init(healthSession: URLSession = .shared) {
        self.healthSession = healthSession
    }

    func endpoint(for runtime: LocalGemmaRuntime, startupTimeoutSeconds: Double, idleTimeoutSeconds: Double) async throws -> LocalGemmaServerEndpoint {
        if let process, process.isRunning, self.runtime == runtime, let endpoint {
            scheduleIdleShutdown(after: idleTimeoutSeconds)
            return endpoint
        }

        await stop()

        let port = Int.random(in: 49_152 ... 65_535)
        let endpoint = LocalGemmaServerEndpoint(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            apiKey: Self.makeAPIKey()
        )
        let process = Process()
        process.executableURL = runtime.serverExecutableURL
        process.arguments = LocalGemmaDefaults.serverArguments(
            modelPath: runtime.modelURL.path,
            port: port,
            apiKey: endpoint.apiKey
        )
        process.standardOutput = Pipe()
        let standardError = Pipe()
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw LLMPostProcessorError.provider("server_start_failed")
        }

        self.process = process
        self.runtime = runtime
        self.endpoint = endpoint

        do {
            try await waitUntilHealthy(
                endpoint: endpoint,
                process: process,
                standardError: standardError,
                timeoutSeconds: startupTimeoutSeconds
            )
        } catch {
            await stop()
            throw error
        }
        scheduleIdleShutdown(after: idleTimeoutSeconds)
        return endpoint
    }

    func scheduleIdleShutdown(after idleTimeoutSeconds: Double) {
        idleShutdownTask?.cancel()
        guard idleTimeoutSeconds > 0 else {
            return
        }
        idleShutdownTask = Task { [weak self] in
            let delayNanos = UInt64(idleTimeoutSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else {
                return
            }
            await self?.stopForIdleTimeout()
        }
    }

    private func waitUntilHealthy(
        endpoint: LocalGemmaServerEndpoint,
        process: Process,
        standardError: Pipe,
        timeoutSeconds: Double
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !process.isRunning {
                let reason = Self.exitReason(
                    status: process.terminationStatus,
                    standardError: standardError
                )
                throw LLMPostProcessorError.provider(reason)
            }

            if await isHealthy(endpoint: endpoint) {
                return
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw LLMPostProcessorError.timeout
    }

    private func isHealthy(endpoint: LocalGemmaServerEndpoint) async -> Bool {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 1
        request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await healthSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return false
            }
            return 200 ..< 300 ~= http.statusCode
        } catch {
            return false
        }
    }

    private func stopForIdleTimeout() async {
        AppLogger.shared.log(.info, "local gemma server idle shutdown")
        await stop()
    }

    func stop() async {
        idleShutdownTask?.cancel()
        idleShutdownTask = nil

        if let stoppingTask {
            await stoppingTask.value
            self.stoppingTask = nil
        }

        let processToStop = process
        process = nil
        runtime = nil
        endpoint = nil

        guard let processToStop else {
            return
        }

        let task = Task.detached(priority: .utility) {
            await Self.terminateAndWait(
                processToStop,
                timeoutSeconds: LocalGemmaDefaults.shutdownTimeoutSeconds
            )
        }
        stoppingTask = task
        await task.value
        stoppingTask = nil
    }

    private static func makeAPIKey() -> String {
        "suniye-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    private static func terminateAndWait(_ process: Process, timeoutSeconds: Double) async {
        guard process.isRunning else {
            return
        }

        process.terminate()
        let waitTask = Task.detached(priority: .utility) {
            process.waitUntilExit()
        }
        let timeoutTask = Task.detached(priority: .utility) {
            let delayNanos = UInt64(max(0, timeoutSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanos)
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }

        await waitTask.value
        timeoutTask.cancel()
    }

    private static func exitReason(status: Int32, standardError: Pipe) -> String {
        let data = standardError.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
            return "server_exited_\(status)"
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let detail = lines.last { !$0.isEmpty } ?? "stderr"
        return "server_exited_\(status)_\(String(detail.prefix(160)))"
    }
}
