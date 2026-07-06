import Foundation
import Darwin

final class LocalGemmaLlamaCppClient: LocalGemmaClient {
    private let locator: LocalGemmaRuntimeLocator
    private let server: LocalGemmaLlamaServer
    private let completionClient: ChatCompletionClient

    init(
        locator: LocalGemmaRuntimeLocator = LocalGemmaRuntimeLocator(),
        server: LocalGemmaLlamaServer? = nil,
        session: URLSession = .shared,
        onModelLoad: (@Sendable (String, Int) -> Void)? = nil,
        onKeepAliveEvicted: (@Sendable (String) -> Void)? = nil
    ) {
        self.locator = locator
        self.server = server ?? LocalGemmaLlamaServer(
            healthSession: session,
            onModelLoad: onModelLoad,
            onKeepAliveEvicted: onKeepAliveEvicted
        )
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

    func isRuntimeWarm() async -> Bool {
        guard case let .success(runtime) = locator.resolve() else {
            return false
        }
        return await server.isWarm(for: runtime)
    }

    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int,
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> String {
        let runtime: LocalGemmaRuntime
        switch locator.resolve() {
        case let .success(resolved):
            runtime = resolved
        case let .failure(availability):
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        // The cold-start `model_load` event is emitted inside the server actor's
        // `start()` success path — the actor serializes startup, so a real load
        // fires exactly one event with the true spawn+health latency, even when a
        // prewarm probe and a real request race for the same (shared) startup.
        let endpoint = try await server.endpoint(
            for: runtime,
            startupTimeoutSeconds: startupTimeoutSeconds,
            idleTimeoutSeconds: idleTimeoutSeconds
        )
        defer {
            Task {
                await server.scheduleIdleShutdown(after: idleTimeoutSeconds)
            }
        }

        // A canceled caller (prewarm probe preempted by a real request) must not
        // occupy the server's single generation slot; startup above is a shared
        // task and completes for the real caller regardless.
        try Task.checkCancellation()

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
    private struct Startup {
        let id: UUID
        let runtime: LocalGemmaRuntime
        let task: Task<LocalGemmaServerEndpoint, Error>
    }

    private let healthSession: URLSession
    /// Fired (model name, cold-start load ms) once per real process start, from
    /// `start()`'s success path. Analytics-only; may be nil.
    private let onModelLoad: (@Sendable (String, Int) -> Void)?
    /// Fired (with the model name) when the keep-alive idle timeout evicts the
    /// loaded model. Analytics-only; may be nil.
    private let onKeepAliveEvicted: (@Sendable (String) -> Void)?
    private var process: Process?
    private var runtime: LocalGemmaRuntime?
    private var endpoint: LocalGemmaServerEndpoint?
    private var startup: Startup?
    private var idleShutdownTask: Task<Void, Never>?
    private var stoppingTask: Task<Void, Never>?

    init(
        healthSession: URLSession = .shared,
        onModelLoad: (@Sendable (String, Int) -> Void)? = nil,
        onKeepAliveEvicted: (@Sendable (String) -> Void)? = nil
    ) {
        self.healthSession = healthSession
        self.onModelLoad = onModelLoad
        self.onKeepAliveEvicted = onKeepAliveEvicted
    }

    func isWarm(for runtime: LocalGemmaRuntime) -> Bool {
        process?.isRunning == true && self.runtime == runtime && endpoint != nil
    }

    func endpoint(for runtime: LocalGemmaRuntime, startupTimeoutSeconds: Double, idleTimeoutSeconds: Double) async throws -> LocalGemmaServerEndpoint {
        if isWarm(for: runtime), let endpoint {
            scheduleIdleShutdown(after: idleTimeoutSeconds)
            return endpoint
        }

        if let startup, startup.runtime == runtime {
            let endpoint = try await startup.task.value
            scheduleIdleShutdown(after: idleTimeoutSeconds)
            return endpoint
        }

        await stop()

        let startupID = UUID()
        let startupTask = Task { [weak self] () throws -> LocalGemmaServerEndpoint in
            guard let self else {
                throw LLMPostProcessorError.provider("server_start_canceled")
            }
            return try await self.start(
                runtime: runtime,
                startupID: startupID,
                startupTimeoutSeconds: startupTimeoutSeconds
            )
        }
        startup = Startup(id: startupID, runtime: runtime, task: startupTask)

        do {
            let endpoint = try await startupTask.value
            if startup?.id == startupID {
                startup = nil
            }
            scheduleIdleShutdown(after: idleTimeoutSeconds)
            return endpoint
        } catch {
            if startup?.id == startupID {
                startup = nil
            }
            throw error
        }
    }

    private func start(
        runtime: LocalGemmaRuntime,
        startupID: UUID,
        startupTimeoutSeconds: Double
    ) async throws -> LocalGemmaServerEndpoint {
        try Task.checkCancellation()
        guard startup?.id == startupID else {
            throw LLMPostProcessorError.provider("server_start_canceled")
        }

        let loadStart = DispatchTime.now()
        let port = Self.findFreePort()
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

        do {
            try await waitUntilHealthy(
                endpoint: endpoint,
                process: process,
                standardError: standardError,
                timeoutSeconds: startupTimeoutSeconds
            )
        } catch {
            await cleanUpFailedStartup(process, startupID: startupID)
            throw error
        }
        guard startup?.id == startupID,
              self.process === process,
              process.isRunning,
              self.runtime == runtime else {
            throw LLMPostProcessorError.provider("server_stopped_during_startup")
        }
        self.endpoint = endpoint
        let loadMs = Int((DispatchTime.now().uptimeNanoseconds - loadStart.uptimeNanoseconds) / 1_000_000)
        onModelLoad?(runtime.model.displayName, loadMs)
        return endpoint
    }

    private func cleanUpFailedStartup(_ processToStop: Process, startupID: UUID) async {
        guard startup?.id == startupID, process === processToStop else {
            return
        }

        startup = nil
        process = nil
        runtime = nil
        endpoint = nil
        await Self.terminateAndWait(
            processToStop,
            timeoutSeconds: LocalGemmaDefaults.shutdownTimeoutSeconds
        )
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
            try Task.checkCancellation()

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
        let evictedModel = runtime?.model.displayName // capture before stop() clears it
        await stop()
        if let evictedModel { onKeepAliveEvicted?(evictedModel) }
    }

    func stop() async {
        idleShutdownTask?.cancel()
        idleShutdownTask = nil

        let startupTaskToCancel = startup?.task
        startup = nil
        startupTaskToCancel?.cancel()

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

    /// Returns an OS-assigned free TCP port (bind to port 0, read it back, release) rather
    /// than a random guess. A random port can collide with an in-use or TIME_WAIT port and
    /// make the server fail to bind — a prime source of CI flakiness for the helper tests.
    private static func findFreePort() -> Int {
        let fallback = Int.random(in: 49_152 ... 65_535)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return fallback }
        defer { close(descriptor) }

        var reuse: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY
        address.sin_port = 0 // let the OS choose a free port

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return fallback }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else { return fallback }
        return Int(UInt16(bigEndian: assigned.sin_port))
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
