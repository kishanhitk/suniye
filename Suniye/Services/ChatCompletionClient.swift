import Foundation

struct ChatCompletionMessage: Encodable {
    let role: String
    let content: String
}

struct ChatCompletionPayload: Encodable {
    let model: String
    let messages: [ChatCompletionMessage]
    let temperature: Int?
    let topK: Int?
    let topP: Int?
    let maxTokens: Int?
    let stream: Bool?

    init(
        model: String,
        messages: [ChatCompletionMessage],
        temperature: Int? = 0,
        topK: Int? = nil,
        topP: Int? = nil,
        maxTokens: Int? = nil,
        stream: Bool? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.maxTokens = maxTokens
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case topK = "top_k"
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case stream
    }
}

enum ChatCompletionRequestFactory {
    static func makeRequest(
        endpointURL: URL,
        apiKey: String,
        payload: ChatCompletionPayload,
        timeoutSeconds: Double
    ) throws -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
}

/// Per-generation counters llama-server attaches to its OpenAI-compatible response
/// (`timings`). Absent from other providers, so always optional on the result.
/// `cachedTokens` is the prompt-prefix reused from the slot's KV cache — the direct
/// measure of whether the prewarm probe primed the cache for this request.
struct ChatCompletionTimings: Decodable, Equatable {
    let promptTokens: Int
    let cachedTokens: Int
    let predictedTokens: Int
    let prefillMs: Int
    let decodeMs: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_n"
        case cachedTokens = "cache_n"
        case predictedTokens = "predicted_n"
        case prefillMs = "prompt_ms"
        case decodeMs = "predicted_ms"
    }

    init(promptTokens: Int, cachedTokens: Int, predictedTokens: Int, prefillMs: Int, decodeMs: Int) {
        self.promptTokens = promptTokens
        self.cachedTokens = cachedTokens
        self.predictedTokens = predictedTokens
        self.prefillMs = prefillMs
        self.decodeMs = decodeMs
    }

    // llama-server emits counts as integers and durations as floats; decode every
    // field as Double so a representation change can't fail the whole response.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) throws -> Int {
            Int((try container.decodeIfPresent(Double.self, forKey: key) ?? 0).rounded())
        }
        promptTokens = try int(.promptTokens)
        cachedTokens = try int(.cachedTokens)
        predictedTokens = try int(.predictedTokens)
        prefillMs = try int(.prefillMs)
        decodeMs = try int(.decodeMs)
    }
}

struct ChatCompletionResult: Equatable {
    let text: String
    let timings: ChatCompletionTimings?
}

final class ChatCompletionClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func complete(
        endpointURL: URL,
        apiKey: String,
        payload: ChatCompletionPayload,
        timeoutSeconds: Double
    ) async throws -> ChatCompletionResult {
        let request = try ChatCompletionRequestFactory.makeRequest(
            endpointURL: endpointURL,
            apiKey: apiKey,
            payload: payload,
            timeoutSeconds: timeoutSeconds
        )

        do {
            let (data, response) = try await withTimeout(seconds: timeoutSeconds) {
                try await self.session.data(for: request)
            }

            guard let http = response as? HTTPURLResponse else {
                throw LLMPostProcessorError.malformedResponse
            }

            switch http.statusCode {
            case 200 ..< 300:
                break
            case 401, 403:
                throw LLMPostProcessorError.unauthorized
            default:
                throw LLMPostProcessorError.provider("http_\(http.statusCode)")
            }

            return try ChatCompletionResponse.extractResult(from: data)
        } catch let error as LLMPostProcessorError {
            throw error
        } catch {
            // Caller canceled (e.g. a prewarm probe preempted by a real request):
            // surface it as cancellation, not as a timeout/network failure. URLSession
            // reports this as URLError(.cancelled) rather than CancellationError.
            if Task.isCancelled {
                throw CancellationError()
            }
            if (error as NSError).code == NSURLErrorTimedOut || error is TimeoutError {
                throw LLMPostProcessorError.timeout
            }
            throw LLMPostProcessorError.network(error.localizedDescription)
        }
    }

    private struct TimeoutError: Error {}

    /// Races the operation against a deadline inside a task group, so the caller's
    /// cancellation propagates structurally into the URLSession request (aborting it)
    /// and a timeout deterministically surfaces as TimeoutError — never as the
    /// URLError(.cancelled) that canceling the losing child produces.
    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw TimeoutError()
            }
            defer {
                group.cancelAll()
            }
            return try await group.next()!
        }
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: Message?
        let text: String?
    }

    struct Message: Decodable {
        let content: Content
    }

    enum Content: Decodable {
        case string(String)
        case parts([Part])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
                return
            }
            self = .parts(try container.decode([Part].self))
        }

        var text: String {
            switch self {
            case let .string(value):
                return value
            case let .parts(parts):
                return parts.compactMap(\.text).joined(separator: "\n")
            }
        }
    }

    struct Part: Decodable {
        let text: String?
    }

    let choices: [Choice]
    /// Diagnostics only — a malformed `timings` block must not fail the response.
    let timings: ChatCompletionTimings?

    enum CodingKeys: String, CodingKey {
        case choices
        case timings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decode([Choice].self, forKey: .choices)
        timings = try? container.decodeIfPresent(ChatCompletionTimings.self, forKey: .timings)
    }

    static func extractResult(from data: Data) throws -> ChatCompletionResult {
        let response: Self
        do {
            response = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw LLMPostProcessorError.malformedResponse
        }
        guard let first = response.choices.first else {
            throw LLMPostProcessorError.malformedResponse
        }
        if let messageText = first.message?.content.text, !messageText.isEmpty {
            return ChatCompletionResult(text: messageText, timings: response.timings)
        }
        if let text = first.text, !text.isEmpty {
            return ChatCompletionResult(text: text, timings: response.timings)
        }
        throw LLMPostProcessorError.malformedResponse
    }
}
