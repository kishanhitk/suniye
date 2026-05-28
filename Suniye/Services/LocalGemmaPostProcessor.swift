import Foundation

enum LocalGemmaDefaults {
    static let providerLogName = "local_gemma"
    static let modelCandidates = [
        LocalGemmaModelCandidate(
            displayName: "Gemma 4 E2B Instruct Q4_K_M",
            repository: "dahus/gemma-4-e2b-it-Q4_K_M-GGUF",
            filename: "gemma-4-e2b-Q4_K_M.gguf",
            expectedSizeText: "3.43 GB"
        ),
        LocalGemmaModelCandidate(
            displayName: "Gemma 4 26B A4B Instruct Q4_K_M",
            repository: "ggml-org/gemma-4-26B-A4B-it-GGUF",
            filename: "gemma-4-26B-A4B-it-Q4_K_M.gguf",
            expectedSizeText: "16.8 GB"
        ),
    ]
    static let modelDisplayName = modelCandidates[0].displayName
    static let modelRepository = modelCandidates[0].repository
    static let modelFilename = modelCandidates[0].filename
    static let expectedSizeText = modelCandidates[0].expectedSizeText
    static let startupTimeoutSeconds = 90.0
    static let generationTimeoutSeconds = 15.0
    static let maxTokens = 256
}

struct LocalGemmaModelCandidate: Equatable {
    let displayName: String
    let repository: String
    let filename: String
    let expectedSizeText: String

    var huggingFaceCacheDirectoryName: String {
        "models--\(repository.replacingOccurrences(of: "/", with: "--"))"
    }
}

protocol LocalGemmaClient {
    var availability: LocalGemmaAvailability { get }
    func generate(instructions: String, prompt: String, maxTokens: Int, timeoutSeconds: Double) async throws -> String
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
            let instructions = makeInstructions(config: config, text: trimmedInput, retrying: attempt > 0)
            let prompt = makePrompt(text: trimmedInput)

            do {
                let raw = try await client.generate(
                    instructions: instructions,
                    prompt: prompt,
                    maxTokens: config.maxTokens,
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
            timeoutSeconds: config.generationTimeoutSeconds
        )
        guard !sanitizeGemmaOutput(output).isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
    }

    private func makeInstructions(config: LocalGemmaMagicFormatConfig, text: String, retrying: Bool) -> String {
        MagicFormatPromptComposer.makeInstructions(
            systemPrompt: config.systemPrompt,
            keywords: config.keywords,
            text: text,
            retrying: retrying
        )
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

private struct LocalGemmaRuntime: Equatable {
    let serverExecutableURL: URL
    let model: LocalGemmaModelCandidate
    let modelURL: URL
}

private enum LocalGemmaRuntimeResolution {
    case success(LocalGemmaRuntime)
    case failure(LocalGemmaAvailability)
}

private struct LocalGemmaRuntimeLocator {
    func resolve() -> LocalGemmaRuntimeResolution {
        guard let serverURL = findExecutable(named: "llama-server") else {
            return .failure(.runtimeUnavailable)
        }
        guard let installedModel = findModelFile() else {
            return .failure(.modelNotInstalled)
        }
        return .success(LocalGemmaRuntime(
            serverExecutableURL: serverURL,
            model: installedModel.model,
            modelURL: installedModel.url
        ))
    }

    private func findExecutable(named name: String) -> URL? {
        let fileManager = FileManager.default
        let bundleCandidates = [
            Bundle.main.url(forAuxiliaryExecutable: name),
            Bundle.main.url(forResource: name, withExtension: nil),
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "LocalLLM"),
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "LocalLLM/bin"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(name),
        ].compactMap { $0 }

        var candidates = bundleCandidates.map(\.path) + [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(
                contentsOf: path
                    .split(separator: ":")
                    .map { String($0) }
                    .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            )
        }

        return candidates
            .lazy
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func findModelFile() -> (model: LocalGemmaModelCandidate, url: URL)? {
        let fileManager = FileManager.default
        var candidates: [(LocalGemmaModelCandidate, URL)] = []

        for model in LocalGemmaDefaults.modelCandidates {
            candidates.append(contentsOf: bundledModelCandidates(model: model).map { (model, $0) })
        }

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let roots = [
                appSupport
                    .appendingPathComponent("Suniye", isDirectory: true)
                    .appendingPathComponent("llm", isDirectory: true),
                appSupport
                    .appendingPathComponent("Suniye", isDirectory: true)
                    .appendingPathComponent("models", isDirectory: true),
            ]
            for model in LocalGemmaDefaults.modelCandidates {
                for root in roots {
                    candidates.append((model, root.appendingPathComponent(model.filename)))
                }
            }
        }

        for model in LocalGemmaDefaults.modelCandidates {
            candidates.append(contentsOf: huggingFaceCacheCandidates(model: model).map { (model, $0) })
        }

        return candidates.first { fileManager.fileExists(atPath: $0.1.path) }
    }

    private func bundledModelCandidates(model: LocalGemmaModelCandidate) -> [URL] {
        let modelURL = URL(fileURLWithPath: model.filename)
        let name = modelURL.deletingPathExtension().lastPathComponent
        let ext = modelURL.pathExtension

        return [
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "LocalLLM"),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "LocalLLM/models"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(model.filename),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("LocalLLM", isDirectory: true)
                .appendingPathComponent(model.filename),
        ].compactMap { $0 }
    }

    private func huggingFaceCacheCandidates(model: LocalGemmaModelCandidate) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let snapshotsRoot = home
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
            .appendingPathComponent(model.huggingFaceCacheDirectoryName, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)

        guard let snapshots = try? FileManager.default.contentsOfDirectory(
            at: snapshotsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return snapshots
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .map { $0.appendingPathComponent(model.filename) }
    }
}

private final class LocalGemmaLlamaCppClient: LocalGemmaClient {
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

    func generate(instructions: String, prompt: String, maxTokens: Int, timeoutSeconds: Double) async throws -> String {
        let runtime: LocalGemmaRuntime
        switch locator.resolve() {
        case let .success(resolved):
            runtime = resolved
        case let .failure(availability):
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        let baseURL = try await server.baseURL(for: runtime, startupTimeoutSeconds: LocalGemmaDefaults.startupTimeoutSeconds)
        let url = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: makePayload(
            instructions: instructions,
            prompt: prompt,
            maxTokens: maxTokens,
            modelName: runtime.model.displayName
        ))

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

    private func makePayload(instructions: String, prompt: String, maxTokens: Int, modelName: String) -> [String: Any] {
        [
            "model": modelName,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
            "temperature": 0,
            "top_p": 1,
            "max_tokens": maxTokens,
            "stream": false,
        ]
    }

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

private actor LocalGemmaLlamaServer {
    private var process: Process?
    private var runtime: LocalGemmaRuntime?
    private var serverURL: URL?

    func baseURL(for runtime: LocalGemmaRuntime, startupTimeoutSeconds: Double) async throws -> URL {
        if let process, process.isRunning, self.runtime == runtime, let serverURL {
            return serverURL
        }

        stop()

        let port = Int.random(in: 49_152 ... 65_535)
        let url = URL(string: "http://127.0.0.1:\(port)")!
        let process = Process()
        process.executableURL = runtime.serverExecutableURL
        process.arguments = [
            "--model", runtime.modelURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--ctx-size", "4096",
            "--parallel", "1",
            "--no-webui",
            "--log-disable",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw LLMPostProcessorError.provider("server_start_failed")
        }

        self.process = process
        self.runtime = runtime
        self.serverURL = url

        try await waitUntilHealthy(baseURL: url, process: process, timeoutSeconds: startupTimeoutSeconds)
        return url
    }

    private func waitUntilHealthy(baseURL: URL, process: Process, timeoutSeconds: Double) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !process.isRunning {
                throw LLMPostProcessorError.provider("server_exited")
            }

            if await isHealthy(baseURL: baseURL) {
                return
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw LLMPostProcessorError.timeout
    }

    private func isHealthy(baseURL: URL) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 1

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

    private func stop() {
        process?.terminate()
        process = nil
        runtime = nil
        serverURL = nil
    }
}
