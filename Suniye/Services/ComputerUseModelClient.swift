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
    You are a desktop UI planning model. Complete the user's task by inspecting the current observation and proposing one next step.

    Return exactly one JSON object. Do not use Markdown fences. Do not include commentary outside the JSON object.

    An action decision has this form. The nested action uses one of these forms:
    {"kind":"action","action":{"kind":"click","x":100,"y":200,"click_count":1,"mouse_button":"left"}}
    {"kind":"action","action":{"kind":"press_key","key":"Return"}}
    {"kind":"action","action":{"kind":"scroll","element_index":3,"direction":"down","pages":1}}
    {"kind":"action","action":{"kind":"click","element_index":3,"click_count":1,"mouse_button":"left"}}
    {"kind":"action","action":{"kind":"type_text","text":"text explicitly required by the task"}}
    {"kind":"action","action":{"kind":"set_value","element_index":3,"value":"text explicitly required by the task"}}
    {"kind":"action","action":{"kind":"drag","from_x":100,"from_y":200,"to_x":300,"to_y":200}}
    {"kind":"action","action":{"kind":"select_text","element_index":3,"text":"exact text","selection_type":"text","prefix":"optional","suffix":"optional"}}
    {"kind":"action","action":{"kind":"perform_secondary_action","element_index":3,"action":"AXPress"}}
    {"kind":"action","action":{"kind":"perform_secondary_action","element_index":3,"action":"AXShowMenu"}}

    Use a target decision with the exact bundle identifier or display name from Available applications when the task requires another application. The host refreshes state for that application and launches it when needed. A target decision does not perform input.
    Use {"kind":"action","action":...} for one action. Use {"kind":"completed","message":"..."} when the task is complete. Use {"kind":"ask_user","question":"..."} when the user must decide something. Use {"kind":"blocked","reason":"..."} when the task cannot continue safely. Use {"kind":"retryable_failure","reason":"..."} only when the current observation is insufficient and another observation may help.

    Click and drag coordinates are relative to the top-left corner of the observed window. Scroll targets an accessibility element and uses direction up, down, left, or right plus a positive page count. Use an accessibility element index only when that index is present in the observation. Use only an action name exposed by that element for secondary actions. Never invent a target, element index, or action name. Never type, set, or select text unless the user's task requires that exact text.
    """
}

struct ComputerUseChatCompletionPayload: Encodable {
    let model: String
    let messages: [ComputerUseChatCompletionMessage]
    let temperature: Int
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
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
        let observation = request.observation
        let target = observation.target
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

        let text = """
        User task:
        \(request.instruction)

        Target application: \(target.application.displayName) (\(target.application.bundleIdentifier))
        Available applications:
        \(availableApplications.isEmpty ? "(none)" : availableApplications)

        Accessibility text:
        \(observation.accessibility.text)

        Recent completed actions:
        \(actionResults.isEmpty ? "(none)" : actionResults)

        Recent failures:
        \(failures.isEmpty ? "(none)" : failures)
        """

        return ComputerUseRenderedModelPrompt(
            text: text,
            screenshot: observation.screenshot
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
            stream: false
        )
        let requestBody = try JSONEncoder().encode(payload)

        do {
            let rawResponse = try await completionClient.complete(
                endpointURL: configuration.endpointURL,
                apiKey: configuration.apiKey,
                requestBody: requestBody,
                timeoutSeconds: configuration.timeoutSeconds
            )
            guard !cancellation.isCancelled else {
                throw CancellationError()
            }
            return try ComputerUseModelDecisionParser.parse(rawResponse)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ComputerUseModelError {
            throw error
        } catch let error as LLMPostProcessorError {
            throw ComputerUseModelError.requestFailed(error.logValue)
        } catch {
            throw ComputerUseModelError.requestFailed("request_failed")
        }
    }
}
