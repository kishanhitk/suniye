import Foundation

struct ComputerUseRemoteModelConfiguration: Equatable, Sendable {
    let endpointURL: URL
    let modelID: String
    let apiKey: String
    let systemPrompt: String
    let timeoutSeconds: Double
    let maxTokens: Int

    init(
        endpointURL: URL,
        modelID: String,
        apiKey: String,
        systemPrompt: String = ComputerUseRemoteModelDefaults.systemPrompt,
        timeoutSeconds: Double = ComputerUseRemoteModelDefaults.timeoutSeconds,
        maxTokens: Int = ComputerUseRemoteModelDefaults.maxTokens
    ) {
        self.endpointURL = endpointURL
        self.modelID = modelID
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
        self.timeoutSeconds = timeoutSeconds
        self.maxTokens = maxTokens
    }

    var validationMessage: String? {
        guard endpointURL.scheme == "https" || endpointURL.scheme == "http" else {
            return "The Computer Use model endpoint must use HTTP or HTTPS."
        }
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "A Computer Use model ID is required."
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "A Computer Use model API key is required."
        }
        guard timeoutSeconds.isFinite, (1 ... 120).contains(timeoutSeconds) else {
            return "The Computer Use model timeout must be between 1 and 120 seconds."
        }
        guard (32 ... 4_096).contains(maxTokens) else {
            return "The Computer Use model token limit must be between 32 and 4,096."
        }
        return nil
    }

}

enum ComputerUseRemoteModelDefaults {
    static let timeoutSeconds = 120.0
    // Reasoning-capable providers can spend the first tokens on hidden
    // reasoning. Keep enough output budget for the final action JSON.
    static let maxTokens = 2_048

    static let systemPrompt = """
    You control one macOS application at a time through its current Accessibility state and window screenshot. Complete the user's task by calling exactly one provided tool for the next step. Do not return ordinary assistant text.

    When the task names another application, call select_target with its display name or bundle identifier. Prefer an exact value from Available applications when present. The host refreshes state for that application and launches it when needed. Selecting a target does not perform input.
    Before any application has been observed, first identify the application from the user's task and return a target decision. Do not default to the frontmost application. If the request can be answered without desktop interaction, complete it without selecting an application.
    Call one action tool for one action. Call completed when the task is complete. Call ask_user when the user must decide something. Call blocked when the task cannot continue safely. Call retryable_failure only when the current observation is insufficient and another observation may help.

    Never return an action before an application observation is present.
    An action is valid only when Observation freshness is fresh. When it is stale, do not return an action; choose a target, request another observation, ask the user, report a block, or complete only if the task is already complete.
    Prefer Accessibility element actions over coordinates. Prefer Accessibility text over the screenshot, but use screenshot coordinates when Accessibility is incomplete or behaves unexpectedly.
    Element indexes and exposed action names belong only to the current observation. Never reuse them after the UI changes. The host captures fresh state after every action before asking for another decision.
    Click and drag coordinates are relative to the top-left corner of the observed window. Scroll targets an Accessibility element and uses direction up, down, left, or right plus a positive page count. Use only an action name exposed by that element for secondary actions. Never invent a target, element index, or action name.
    Key presses and typed text target the observed application and cannot invoke global shortcuts. Treat newline characters in typed text as Return, which can submit a form or send a message. Never type, set, or select text unless the user's task requires that exact text.
    """
}

struct ComputerUseChatCompletionPayload: Encodable {
    let model: String
    let messages: [ComputerUseChatCompletionMessage]
    let temperature: Int
    let maxTokens: Int
    let stream: Bool
    let tools: [ComputerUseChatCompletionTool]
    let toolChoice: String
    let parallelToolCalls: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
    }
}

struct ComputerUseChatCompletionMessage: Encodable {
    let role: String
    let content: ComputerUseChatCompletionContent
}

enum ComputerUseChatCompletionContent: Encodable {
    case text(String)
    case parts([ComputerUseChatCompletionPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value):
            try container.encode(value)
        case let .parts(parts):
            try container.encode(parts)
        }
    }
}

enum ComputerUseChatCompletionPart: Encodable {
    case text(String)
    case image(url: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private struct ImageURL: Encodable {
        let url: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case let .image(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURL(url: url), forKey: .imageURL)
        }
    }
}

struct ComputerUseRenderedModelPrompt: Equatable, Sendable {
    let text: String
    let screenshot: ComputerUseScreenshot?
}

enum ComputerUseModelPromptRenderer {
    static func render(request: ComputerUseModelRequest) -> ComputerUseRenderedModelPrompt {
        let actionResults = request.recentActionResults
            .map { "- \($0.action.summary) at \($0.completedAt.ISO8601Format())" }
            .joined(separator: "\n")
        let failures = request.recentFailureMessages
            .map { "- \($0)" }
            .joined(separator: "\n")
        let availableApplications = request.availableApplications
            .map {
                "- \($0.displayName) (\($0.bundleIdentifier)); running=\($0.isRunning)"
            }
            .joined(separator: "\n")
        let conversation = request.conversation
            .map { message in
                let speaker = message.role == .user ? "User" : "Assistant"
                return "\(speaker): \(message.text)"
            }
            .joined(separator: "\n")

        let observationText: String
        let screenshot: ComputerUseScreenshot?
        if let observationContext = request.observationContext {
            let observation = observationContext.observation
            let freshness = observationContext.freshness
            observationText = """
            Observation freshness: \(freshness.rawValue)
            Actions allowed from this observation: \(freshness.allowsActions ? "yes" : "no")
            Target application: \(observation.target.application.displayName) (\(observation.target.application.bundleIdentifier))

            Accessibility text:
            \(observation.accessibility.text)
            """
            screenshot = observation.screenshot
        } else {
            observationText = """
            Observation: (none; choose the target application before requesting an action)
            Actions allowed from this observation: no
            Target application: (not selected)
            """
            screenshot = nil
        }

        let text = """
        Prior conversation:
        \(conversation.isEmpty ? "(none)" : conversation)

        User task:
        \(request.instruction)

        \(observationText)

        Available applications:
        \(availableApplications.isEmpty ? "(none)" : availableApplications)

        Recent completed actions:
        \(actionResults.isEmpty ? "(none)" : actionResults)

        Recent failures:
        \(failures.isEmpty ? "(none)" : failures)
        """

        return ComputerUseRenderedModelPrompt(
            text: text,
            screenshot: screenshot
        )
    }

}

enum ComputerUseModelDecisionParser {
    static func parse(_ rawResponse: String) throws -> ComputerUseModelDecision {
        let normalized = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ComputerUseModelError.invalidResponse("the response was empty")
        }

        let json = stripMarkdownFence(from: normalized)
        let data = Data(json.utf8)

        let decision: ComputerUseModelDecision
        do {
            decision = try JSONDecoder().decode(ComputerUseModelDecision.self, from: data)
        } catch {
            throw ComputerUseModelError.invalidResponse("the response did not match the action schema")
        }
        if let validationMessage = decision.validationMessage {
            throw ComputerUseModelError.invalidResponse(validationMessage)
        }
        return decision
    }

    private static func stripMarkdownFence(from value: String) -> String {
        guard value.hasPrefix("```") else {
            return value
        }

        var lines = value.components(separatedBy: .newlines)
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class OpenAICompatibleComputerUseModelClient: ComputerUseModelClient {
    private let configuration: ComputerUseRemoteModelConfiguration
    private let completionClient: ChatCompletionClient

    init(
        configuration: ComputerUseRemoteModelConfiguration,
        completionClient: ChatCompletionClient = ChatCompletionClient()
    ) {
        self.configuration = configuration
        self.completionClient = completionClient
    }

    func decide(
        request: ComputerUseModelRequest,
        cancellation: ComputerUseCancellationToken
    ) async throws -> ComputerUseModelDecision {
        if let validationMessage = configuration.validationMessage {
            throw ComputerUseModelError.requestFailed(validationMessage)
        }
        guard !cancellation.isCancelled else {
            throw CancellationError()
        }

        let rendered = ComputerUseModelPromptRenderer.render(request: request)
        let content: ComputerUseChatCompletionContent
        if let screenshot = rendered.screenshot {
            let dataURL = "data:\(screenshot.mimeType);base64,\(screenshot.data.base64EncodedString())"
            content = .parts([
                .text(rendered.text),
                .image(url: dataURL),
            ])
        } else {
            content = .text(rendered.text)
        }
        let payload = ComputerUseChatCompletionPayload(
            model: configuration.modelID,
            messages: [
                ComputerUseChatCompletionMessage(
                    role: "system",
                    content: .text(configuration.systemPrompt)
                ),
                ComputerUseChatCompletionMessage(role: "user", content: content),
            ],
            temperature: 0,
            maxTokens: configuration.maxTokens,
            stream: false,
            tools: ComputerUseModelTools.all,
            toolChoice: "required",
            parallelToolCalls: false
        )
        let requestBody = try JSONEncoder().encode(payload)

        do {
            let response = try await completionClient.completeResult(
                endpointURL: configuration.endpointURL,
                apiKey: configuration.apiKey,
                requestBody: requestBody,
                timeoutSeconds: configuration.timeoutSeconds
            )
            guard !cancellation.isCancelled else {
                throw CancellationError()
            }
            if let toolCall = response.toolCalls.first {
                guard response.toolCalls.count == 1 else {
                    throw ComputerUseModelError.invalidResponse(
                        "the response must contain exactly one tool call"
                    )
                }
                return try ComputerUseModelToolCallParser.parse(
                    name: toolCall.name,
                    arguments: toolCall.arguments
                )
            }
            guard let text = response.text else {
                throw ComputerUseModelError.invalidResponse("the response did not contain a decision")
            }
            return try ComputerUseModelDecisionParser.parse(text)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ComputerUseModelError {
            throw error
        } catch let error as LLMPostProcessorError {
            throw ComputerUseModelError.requestFailed(
                error.errorDescription ?? error.logValue
            )
        } catch {
            throw ComputerUseModelError.requestFailed("request_failed")
        }
    }
}
