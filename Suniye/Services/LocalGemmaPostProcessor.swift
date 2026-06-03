import Foundation

enum LocalGemmaDefaults {
    static let providerLogName = "local_gemma"
    static let modelID = LocalLLMModelCatalog.preferredModelID
    static let modelEntry = LocalLLMModelCatalog.entry(for: modelID)
    static let modelDisplayName = modelEntry.displayName
    static let modelRepository = modelEntry.repository
    static let modelFilename = modelEntry.filename
    static let expectedSizeText = modelEntry.expectedSizeText
    static let startupTimeoutSeconds = 90.0
    static let generationTimeoutSeconds = 15.0
    static let idleTimeoutSeconds = 180.0
    static let maxTokens = 256

    static func serverArguments(modelPath: String, port: Int, apiKey: String) -> [String] {
        return [
            "--model", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--ctx-size", "4096",
            "--parallel", "1",
            "--reasoning", "off",
            "--api-key", apiKey,
            "--no-webui",
            "--log-disable",
        ]
    }
}

protocol LocalGemmaClient {
    var availability: LocalGemmaAvailability { get }
    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int,
        startupTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> String
}

final class LocalGemmaPostProcessor: LocalGemmaMagicFormatPostProcessor {
    private let client: LocalGemmaClient

    init(client: LocalGemmaClient = LocalGemmaLlamaCppClient()) {
        self.client = client
    }

    var availability: LocalGemmaAvailability {
        client.availability
    }

    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        var lastInvalidOutputWasEmpty = false
        for attempt in 0 ..< 2 {
            let instructions = makeInstructions(config: config, retrying: attempt > 0)
            let prompt = makePrompt(text: trimmedInput)

            do {
                let raw = try await client.generate(
                    instructions: instructions,
                    prompt: prompt,
                    maxTokens: config.maxTokens,
                    startupTimeoutSeconds: config.startupTimeoutSeconds,
                    timeoutSeconds: config.generationTimeoutSeconds
                )
                let sanitized = sanitizeGemmaOutput(raw)
                if MagicFormatOutputSanitizer.isValidPlainText(sanitized, for: trimmedInput) {
                    return sanitized
                }
                lastInvalidOutputWasEmpty = sanitized.isEmpty
            } catch let error as LLMPostProcessorError {
                throw error
            } catch {
                throw LLMPostProcessorError.provider(error.localizedDescription)
            }
        }

        throw lastInvalidOutputWasEmpty ? LLMPostProcessorError.emptyOutput : LLMPostProcessorError.malformedResponse
    }

    func testSetup(config: LocalGemmaMagicFormatConfig) async throws {
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        let output = try await client.generate(
            instructions: "Reply with OK.",
            prompt: "Connection test.",
            maxTokens: 8,
            startupTimeoutSeconds: config.startupTimeoutSeconds,
            timeoutSeconds: config.generationTimeoutSeconds
        )
        guard !sanitizeGemmaOutput(output).isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
    }

    private func makeInstructions(config: LocalGemmaMagicFormatConfig, retrying: Bool) -> String {
        var sections = [config.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)]

        if !config.keywords.isEmpty {
            sections.append("Vocabulary terms to preserve exactly when present: \(config.keywords.joined(separator: ", ")).")
        }

        if retrying {
            sections.append("Retry correction: return only the cleaned transcript text. Do not add wrapper text, markdown, quotes around the answer, or extra commentary.")
        }

        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func makePrompt(text: String) -> String {
        """
        <transcript>
        \(text)
        </transcript>
        """
    }

    private func sanitizeGemmaOutput(_ raw: String) -> String {
        var sanitized = MagicFormatOutputSanitizer.sanitize(raw)

        if let thoughtEnd = sanitized.range(of: "<channel|>", options: .backwards) {
            sanitized = String(sanitized[thoughtEnd.upperBound...])
        }

        let controlTokens = [
            "<|channel>final\n",
            "<|channel>final",
            "<end_of_turn>",
            "<eos>",
        ]
        for token in controlTokens {
            sanitized = sanitized.replacingOccurrences(of: token, with: "")
        }

        return MagicFormatOutputSanitizer.sanitize(sanitized)
    }
}

struct LocalGemmaRuntime: Equatable {
    let serverExecutableURL: URL
    let model: LocalLLMModelCatalogEntry
    let modelURL: URL
}

enum LocalGemmaRuntimeResolution {
    case success(LocalGemmaRuntime)
    case failure(LocalGemmaAvailability)
}

struct LocalGemmaRuntimeLocator {
    let modelManager: LocalLLMModelManagerProtocol
    let fileManager: FileManager

    init(
        modelManager: LocalLLMModelManagerProtocol = LocalLLMModelManager(),
        fileManager: FileManager = .default
    ) {
        self.modelManager = modelManager
        self.fileManager = fileManager
    }

    func resolve() -> LocalGemmaRuntimeResolution {
        guard modelManager.isHardwareSupported else {
            return .failure(.unsupportedHardware)
        }
        guard modelManager.isInstalled(LocalGemmaDefaults.modelID),
              let modelURL = try? modelManager.modelFileURL(for: LocalGemmaDefaults.modelID) else {
            return .failure(.modelNotInstalled)
        }
        guard let serverURL = findExecutable(named: "llama-server") else {
            return .failure(.runtimeUnavailable)
        }
        return .success(LocalGemmaRuntime(
            serverExecutableURL: serverURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: modelURL
        ))
    }

    private func findExecutable(named name: String) -> URL? {
        if let override = ProcessInfo.processInfo.environment["SUNIYE_LLAMA_SERVER_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let bundleCandidates = [
            Bundle.main.url(forAuxiliaryExecutable: name),
            Bundle.main.url(forResource: name, withExtension: nil),
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "LocalLLM"),
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "LocalLLM/bin"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(name),
        ].compactMap { $0 }

        return bundleCandidates
            .lazy
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

final class LocalGemmaLlamaCppClient: LocalGemmaClient {
    private let locator: LocalGemmaRuntimeLocator
    private let server: LocalGemmaLlamaServer
    private let session: URLSession

    init(
        locator: LocalGemmaRuntimeLocator = LocalGemmaRuntimeLocator(),
        server: LocalGemmaLlamaServer = LocalGemmaLlamaServer(),
        session: URLSession = .shared
    ) {
        self.locator = locator
        self.server = server
        self.session = session
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

        let request = try LocalGemmaCompletionRequestFactory.makeRequest(
            endpoint: endpoint,
            instructions: instructions,
            prompt: prompt,
            maxTokens: maxTokens,
            modelName: runtime.model.displayName,
            timeoutSeconds: timeoutSeconds
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMPostProcessorError.malformedResponse
            }
            guard 200 ..< 300 ~= http.statusCode else {
                throw LLMPostProcessorError.provider("http_\(http.statusCode)")
            }
            return try extractText(from: data)
        } catch let error as LLMPostProcessorError {
            throw error
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw LLMPostProcessorError.timeout
            }
            throw LLMPostProcessorError.network(error.localizedDescription)
        }
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
        let url = endpoint.baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: makePayload(
            instructions: instructions,
            prompt: prompt,
            maxTokens: maxTokens,
            modelName: modelName
        ))
        return request
    }

    private static func makePayload(instructions: String, prompt: String, maxTokens: Int, modelName: String) -> [String: Any] {
        let userContent = """
        \(instructions)

        \(prompt)
        """

        return [
            "model": modelName,
            "messages": [
                ["role": "user", "content": userContent],
            ],
            "temperature": 0,
            "top_k": 1,
            "top_p": 1,
            "max_tokens": maxTokens,
            "stream": false,
        ]
    }
}

private extension LocalGemmaLlamaCppClient {
    private func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else {
            throw LLMPostProcessorError.malformedResponse
        }

        if let message = first["message"] as? [String: Any],
           let content = message["content"] {
            if let text = content as? String {
                return text
            }
            if let parts = content as? [[String: Any]] {
                let collected = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !collected.isEmpty {
                    return collected
                }
            }
        }

        if let text = first["text"] as? String {
            return text
        }

        throw LLMPostProcessorError.malformedResponse
    }
}

actor LocalGemmaLlamaServer {
    private var process: Process?
    private var runtime: LocalGemmaRuntime?
    private var endpoint: LocalGemmaServerEndpoint?
    private var idleShutdownTask: Task<Void, Never>?

    func endpoint(for runtime: LocalGemmaRuntime, startupTimeoutSeconds: Double, idleTimeoutSeconds: Double) async throws -> LocalGemmaServerEndpoint {
        if let process, process.isRunning, self.runtime == runtime, let endpoint {
            scheduleIdleShutdown(after: idleTimeoutSeconds)
            return endpoint
        }

        stop()

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
            stop()
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
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return false
            }
            return 200 ..< 300 ~= http.statusCode
        } catch {
            return false
        }
    }

    private func stopForIdleTimeout() {
        AppLogger.shared.log(.info, "local gemma server idle shutdown")
        stop()
    }

    private func stop() {
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        process?.terminate()
        process = nil
        runtime = nil
        endpoint = nil
    }

    private static func makeAPIKey() -> String {
        "suniye-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
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
