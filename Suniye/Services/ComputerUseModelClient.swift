import Foundation

struct ComputerUseRemoteModelConfiguration: Equatable, Sendable {
    let endpointURL: URL
    let modelID: String
    let apiKey: String
    let timeoutSeconds: Double
    let maxTokens: Int

    init(
        endpointURL: URL,
        modelID: String,
        apiKey: String,
        timeoutSeconds: Double = 120,
        maxTokens: Int = 2_048
    ) {
        self.endpointURL = endpointURL
        self.modelID = modelID
        self.apiKey = apiKey
        self.timeoutSeconds = timeoutSeconds
        self.maxTokens = maxTokens
    }
}

enum ComputerUseModelRole: String, Encodable, Equatable, Sendable {
    case system
    case user
    case assistant
    case tool
}

struct ComputerUseModelMessage: Encodable, Equatable, Sendable {
    let role: ComputerUseModelRole
    let content: ComputerUseModelContent?
    let toolCalls: [ComputerUseModelWireToolCall]?
    let toolCallID: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    static func text(role: ComputerUseModelRole, text: String) -> Self {
        Self(
            role: role,
            content: .text(text),
            toolCalls: nil,
            toolCallID: nil
        )
    }

    static func toolCall(id: String, name: String, arguments: String) -> Self {
        Self(
            role: .assistant,
            content: nil,
            toolCalls: [.init(id: id, name: name, arguments: arguments)],
            toolCallID: nil
        )
    }

    static func toolResult(id: String, content: String) -> Self {
        Self(
            role: .tool,
            content: .text(content),
            toolCalls: nil,
            toolCallID: id
        )
    }

    static func image(role: ComputerUseModelRole, text: String, dataURL: String) -> Self {
        Self(
            role: role,
            content: .parts([.text(text), .image(dataURL)]),
            toolCalls: nil,
            toolCallID: nil
        )
    }

    /// The one shape a screenshot takes in model context, live and replayed.
    static func screenshot(app: String, dataURL: String) -> Self {
        .image(role: .user, text: "Current \(app) screenshot.", dataURL: dataURL)
    }
}

enum ComputerUseModelContent: Encodable, Equatable, Sendable {
    case text(String)
    case parts([ComputerUseModelContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(text):
            try container.encode(text)
        case let .parts(parts):
            try container.encode(parts)
        }
    }
}

enum ComputerUseModelContentPart: Encodable, Equatable, Sendable {
    case text(String)
    case image(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private struct ImageURL: Encodable, Equatable, Sendable {
        let url: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURL(url: url), forKey: .imageURL)
        }
    }
}

struct ComputerUseModelWireToolCall: Encodable, Equatable, Sendable {
    struct Function: Encodable, Equatable, Sendable {
        let name: String
        let arguments: String
    }

    let id: String
    let type = "function"
    let function: Function

    init(id: String, name: String, arguments: String) {
        self.id = id
        function = Function(name: name, arguments: arguments)
    }
}

enum ComputerUseModelResponse: Equatable, Sendable {
    case text(String)
    case toolCall(id: String, name: String, arguments: String)
}

protocol ComputerUseModelServing: Sendable {
    func respond(to messages: [ComputerUseModelMessage]) async throws -> ComputerUseModelResponse
}

struct ComputerUseModelRetryPolicy: Equatable, Sendable {
    static let referenceAligned = Self(maximumRetries: 4, baseDelayMilliseconds: 200)

    let maximumRetries: Int
    let baseDelayMilliseconds: Int64

    func shouldRetry(_ error: LLMPostProcessorError) -> Bool {
        switch error {
        case .network, .timeout:
            return true
        case let .provider(reason):
            guard reason.hasPrefix("http_"),
                  let statusCode = Int(reason.dropFirst("http_".count)) else {
                return false
            }
            return (500 ... 599).contains(statusCode)
        case .malformedResponse, .emptyOutput:
            return true
        case .invalidConfiguration, .unauthorized:
            return false
        }
    }

    func delay(afterFailedAttempt attempt: Int, jitter: Double) -> Duration {
        let boundedJitter = min(max(jitter, 0.9), 1.1)
        let multiplier = Int64(1 << attempt)
        let milliseconds = Int64(
            (Double(baseDelayMilliseconds * multiplier) * boundedJitter).rounded()
        )
        return .milliseconds(milliseconds)
    }
}

protocol ComputerUseModelRetrySleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemComputerUseModelRetrySleeper: ComputerUseModelRetrySleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

enum ComputerUseModelError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case invalidResponse(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return "Invalid Computer Use model configuration: \(message)"
        case let .invalidResponse(message):
            return "The Computer Use model returned an invalid response: \(message)"
        case let .requestFailed(message):
            return "The Computer Use model request failed: \(message)"
        }
    }
}

final class ComputerUseRemoteModelClient: ComputerUseModelServing {
    private let configuration: ComputerUseRemoteModelConfiguration
    private let completionClient: ChatCompletionClient
    private let retryPolicy: ComputerUseModelRetryPolicy
    private let retrySleeper: any ComputerUseModelRetrySleeping
    private let retryJitter: @Sendable () -> Double

    init(
        configuration: ComputerUseRemoteModelConfiguration,
        completionClient: ChatCompletionClient = ChatCompletionClient(),
        retryPolicy: ComputerUseModelRetryPolicy = .referenceAligned,
        retrySleeper: any ComputerUseModelRetrySleeping = SystemComputerUseModelRetrySleeper(),
        retryJitter: @escaping @Sendable () -> Double = { Double.random(in: 0.9 ..< 1.1) }
    ) {
        self.configuration = configuration
        self.completionClient = completionClient
        self.retryPolicy = retryPolicy
        self.retrySleeper = retrySleeper
        self.retryJitter = retryJitter
    }

    func respond(
        to messages: [ComputerUseModelMessage]
    ) async throws -> ComputerUseModelResponse {
        try validateConfiguration()
        let payload = ComputerUseModelPayload(
            model: configuration.modelID,
            messages: [
                .text(role: .system, text: ComputerUseModelInstructions.text),
            ] + messages,
            maxTokens: configuration.maxTokens,
            stream: false,
            tools: ComputerUseModelToolCatalog.all,
            toolChoice: "auto",
            parallelToolCalls: false
        )
        let requestBody = try JSONEncoder().encode(payload)

        do {
            let result = try await complete(requestBody: requestBody)
            guard result.toolCalls.count <= 1 else {
                throw ComputerUseModelError.invalidResponse(
                    "expected at most one tool call"
                )
            }
            if let call = result.toolCalls.first {
                return .toolCall(
                    id: call.id,
                    name: call.name,
                    arguments: call.arguments
                )
            }
            guard let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw ComputerUseModelError.invalidResponse("missing text or tool call")
            }
            return .text(text)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ComputerUseModelError {
            throw error
        } catch let error as LLMPostProcessorError {
            throw ComputerUseModelError.requestFailed(
                error.errorDescription ?? error.logValue
            )
        } catch {
            throw ComputerUseModelError.requestFailed(error.localizedDescription)
        }
    }

    private func complete(requestBody: Data) async throws -> ChatCompletionResult {
        for attempt in 0 ... retryPolicy.maximumRetries {
            do {
                return try await completionClient.completeResult(
                    endpointURL: configuration.endpointURL,
                    apiKey: configuration.apiKey,
                    requestBody: requestBody,
                    timeoutSeconds: configuration.timeoutSeconds
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LLMPostProcessorError {
                guard attempt < retryPolicy.maximumRetries,
                      retryPolicy.shouldRetry(error) else {
                    throw error
                }
                try await retrySleeper.sleep(
                    for: retryPolicy.delay(
                        afterFailedAttempt: attempt,
                        jitter: retryJitter()
                    )
                )
            }
        }
        preconditionFailure("The model retry loop must return or throw")
    }

    private func validateConfiguration() throws {
        guard ["http", "https"].contains(configuration.endpointURL.scheme?.lowercased()) else {
            throw ComputerUseModelError.invalidConfiguration(
                "the endpoint must use HTTP or HTTPS"
            )
        }
        guard !configuration.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComputerUseModelError.invalidConfiguration("a model is required")
        }
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComputerUseModelError.invalidConfiguration("an API key is required")
        }
    }
}

private struct ComputerUseModelPayload: Encodable {
    let model: String
    let messages: [ComputerUseModelMessage]
    let maxTokens: Int
    let stream: Bool
    let tools: [ComputerUseModelTool]
    let toolChoice: String
    let parallelToolCalls: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case stream
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
    }
}

private enum ComputerUseModelInstructions {
    static let text = """
    Use the provided app-scoped macOS tools to complete the user's task. Choose the application from the task, prior conversation, built-in macOS applications, and observed state.

    When the application is evident, start with get_app_state using its display name or bundle identifier. Call list_apps only when the application cannot be identified. Do not call list_apps just to resolve an app already named by the user. get_app_state may launch an application in the background, so there is no separate open-app step. A task may use an application or system interface that you select because it is appropriate to the requested outcome. The current app content may be unrelated to the user's request or left over from an earlier task. Match the requested subject before acting on a visible result; navigate or search instead of opening unrelated content.

    Call get_app_state once per assistant turn before interacting with an application. This runtime executes one tool call per model decision, so call get_app_state after every UI action and before choosing the next action. Re-derive element indexes and exposed Accessibility action names from the latest observation instead of reusing stale values. By default get_app_state may return an Accessibility diff; use disableDiff only when you need a complete tree or did not retain the earlier tree. Prefer indexed Accessibility actions and text. Use the attached window screenshot, coordinate clicks, key presses, or text input when Accessibility information is incomplete or behaves unexpectedly.

    App names, full application paths, and bundle identifiers are accepted. If an operation fails when using a display name, call list_apps and immediately retry the same operation with the returned bundle identifier before trying another recovery path. If the requested app is not present, say that it is unavailable; never substitute or inspect an unrelated app. Coordinate clicks and drags are relative to the observed window. For click, use either element_index or x and y; omit element_index for a coordinate click. Use only secondary actions explicitly exposed by the current element. Key presses and typed text are app-scoped. Newlines in typed text can submit a form or send a message.

    The runtime waits for the application to settle after actions. A target appearing in a list, search result, menu, or tree proves only that the target exists; it does not prove that the target was opened, selected, clicked, changed, or otherwise acted on. A focused or selected item is not proof that it was activated or opened. If a click focuses the intended control without activating it, press Return, then observe again. If the UI does not behave as expected, observe the latest state and choose another supported action; do not repeat an action that left the observed state unchanged.

    If the user requested a UI change and the latest observation does not already show that exact end state, you must call an action tool. You may not report success for a requested UI change after an observation-only path. After the action, call get_app_state again and confirm the requested result in the fresh state captured after that action. Return a concise assistant response only when the requested outcome is verified or when user input is required.
    """
}
