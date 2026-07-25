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
    ) async throws -> String {
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

            return try ChatCompletionResponse.extractText(from: data)
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

// Internal (not private) so `extractText` — the response-shape tolerance that
// keeps reasoning / function-calling models from decoding as malformedResponse —
// is directly unit-testable with canned JSON.
struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: Message?
        let text: String?
    }

    struct Message: Decodable {
        // Optional: reasoning models and native function-calling replies send
        // `"content": null`, which a non-optional field would fail to decode —
        // sinking the whole response as malformedResponse even when a usable
        // answer is present in `tool_calls`.
        let content: Content?
        let toolCalls: [ToolCallDTO]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCallDTO: Decodable {
        struct Function: Decodable {
            let name: String?
            let arguments: String?
        }
        let function: Function?
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

    static func extractText(from data: Data) throws -> String {
        let response: Self
        do {
            response = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw LLMPostProcessorError.malformedResponse
        }
        guard let first = response.choices.first else {
            throw LLMPostProcessorError.malformedResponse
        }
        if let messageText = first.message?.content?.text, !messageText.isEmpty {
            return messageText
        }
        if let text = first.text, !text.isEmpty {
            return text
        }
        // Native function/tool call (content is null in this shape): reconstruct
        // the {"tool","arguments"} JSON the agent's ToolCallParser expects, so a
        // model that function-calls instead of emitting text still drives the loop.
        if let function = first.message?.toolCalls?.first?.function,
           let name = function.name, !name.isEmpty {
            let arguments = (function.arguments.map { $0.isEmpty ? "{}" : $0 }) ?? "{}"
            return "{\"tool\":\"\(name)\",\"arguments\":\(arguments)}"
        }
        throw LLMPostProcessorError.malformedResponse
    }
}
