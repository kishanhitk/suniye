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

enum ComputerUseModelInstructions {
    static let text = """
    Control macOS by writing JavaScript in the node_repl tool. The runtime pre-injects `computer` (the Computer Use API) and `nodeRepl.write(text)` for text output. Top-level await is supported; await every `computer` call. One node_repl call may run several actions in sequence — observe, act, then observe again — so prefer batching a coherent step into one script over many tiny calls.

    The `computer` API (all methods are async):
    computer.list_apps() -> array of { id, displayName, isRunning, isFrontmost }. The frontmost app is what the user is looking at.
    computer.get_app_state({ app, disableDiff }) -> { app, text, screenshot }. `text` is the Accessibility tree with element indexes; the window screenshot is attached to you automatically. Launches the app in the background if needed.
    computer.click({ app, element_index }) or computer.click({ app, x, y, mouse_button, click_count }). Use element_index from the latest observation, or window-relative screenshot coordinates; omit element_index for a coordinate click.
    computer.set_value({ app, element_index, value }) — replace an editable element's value.
    computer.type_text({ app, text }) — type into the current focus. A newline can submit a form or send a message.
    computer.press_key({ app, key }) — a key or chord in X keysym syntax, such as "Return", "Tab", "Control_L+a", "Super_L+space", or "KP_0"; aliases like "Control", "Alt", "Shift" are accepted.
    computer.scroll({ app, element_index, direction, pages }) — direction is up, down, left, or right.
    computer.select_text({ app, element_index, text, prefix, suffix, selection_type }) — select text or place the cursor around it.
    computer.perform_secondary_action({ app, element_index, action }) — invoke an Accessibility action the element exposes; use only exposed action names.
    computer.drag({ app, from_x, from_y, to_x, to_y }) — drag between window-relative coordinates.
    computer.set_voice_activation({ enabled }) — turn Suniye's always-listening Voice Activation on or off. Call with enabled=false when the user asks to stop listening, in any phrasing or language. This controls listening only; it does not end the task or conversation.

    Each node_repl call is independent: top-level variables do not persist between calls, so re-observe with computer.get_app_state at the start of a script before acting. Call get_app_state after every UI action and before choosing the next, and re-derive element indexes and exposed action names from the latest observation instead of reusing stale values. get_app_state returns an Accessibility diff by default; pass disableDiff when you need the full tree or did not retain the earlier one. Prefer indexed Accessibility actions and text; fall back to the attached screenshot, coordinate clicks, key presses, or typed text when Accessibility is incomplete or behaves unexpectedly.

    When the application is evident, start with computer.get_app_state using its display name or bundle identifier. Call computer.list_apps only when the application cannot be identified, never just to resolve an app the user already named. If an operation fails by display name, retry it once with the bundle identifier from list_apps before another recovery path. If the requested app is not present, say it is unavailable; never substitute or inspect an unrelated app. The current app content may be unrelated to the request or left over from an earlier task — match the requested subject before acting; navigate or search instead of opening unrelated content.

    A target appearing in a list, search result, menu, or tree proves only that it exists, not that it was opened, selected, clicked, or activated. If a click focuses a control without activating it, press Return, then observe again. If the UI does not change as expected, observe the latest state and choose another supported action; do not repeat an action that left the observed state unchanged. If the user requested a UI change and the latest observation does not already show that exact end state, perform an action; never report success for a requested change after an observation-only path. After acting, observe again and confirm the requested result in the fresh state before reporting success.

    When the user asks about the screen, or the task does not name an application, call computer.list_apps and observe the app marked isFrontmost — that is what the user is looking at. Never launch or observe an application the task does not require; opening a browser is justified only when the task itself needs the web. get_app_state launches its target if it is not running, so choosing an app is choosing to open it.

    Your responses are spoken aloud to the user, not displayed as text. Write every assistant response the way a person answers out loud: plain sentences, no Markdown, no formatting characters, no headings, no bullet or numbered lists, no tables, no code blocks, no URLs. Say numbers and units the way they are spoken. Lead with the answer or outcome. Keep reports of completed actions to one to three short sentences.

    When the task asks a question or asks you to read, summarize, or explain content, the final response is the content itself: give the summary, the answer, or the reading, spoken as a short paragraph. Never respond with a statement that the information was found, that the observation was sufficient, or a description of your own process; that is a non-answer. If the needed content is already visible in the latest observation, answer directly without another node_repl call.
    """
}
