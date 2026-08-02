import Foundation

struct ComputerUseRemoteModelConfiguration: Equatable, Sendable {
    let endpointURL: URL
    let modelID: String
    let apiKey: String
    let systemPrompt: String
    let timeoutSeconds: Double
    let maxTokens: Int
    let allowsScreenshotUpload: Bool

    init(
        endpointURL: URL,
        modelID: String,
        apiKey: String,
        systemPrompt: String = ComputerUseRemoteModelDefaults.systemPrompt,
        timeoutSeconds: Double = ComputerUseRemoteModelDefaults.timeoutSeconds,
        maxTokens: Int = ComputerUseRemoteModelDefaults.maxTokens,
        allowsScreenshotUpload: Bool = false
    ) {
        self.endpointURL = endpointURL
        self.modelID = modelID
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
        self.timeoutSeconds = timeoutSeconds
        self.maxTokens = maxTokens
        self.allowsScreenshotUpload = allowsScreenshotUpload
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

    func withScreenshotUpload(_ allowed: Bool) -> Self {
        Self(
            endpointURL: endpointURL,
            modelID: modelID,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            timeoutSeconds: timeoutSeconds,
            maxTokens: maxTokens,
            allowsScreenshotUpload: allowed
        )
    }
}

enum ComputerUseRemoteModelDefaults {
    static let timeoutSeconds = 120.0
    static let maxTokens = 512

    static let systemPrompt = """
    You are a desktop UI planning model. Complete the user's task by inspecting the current observation and proposing one next step.

    Return exactly one JSON object. Do not use Markdown fences. Do not include commentary outside the JSON object.

    An action object uses one of these forms:
    {"kind":"click","x":100,"y":200}
    {"kind":"key_press","key":{"kind":"named","value":"return"},"modifiers":{"command":false,"option":false,"control":false,"shift":false,"function":false}}
    {"kind":"scroll","horizontal":0,"vertical":-400}
    {"kind":"type_text","text":"text explicitly required by the task"}
    {"kind":"semantic","elementIndex":3,"action":"AXPress"}

    Use {"kind":"action","action":...} for one action. Use {"kind":"completed","message":"..."} when the task is complete. Use {"kind":"ask_user","question":"..."} when the user must decide something. Use {"kind":"blocked","reason":"..."} when the task cannot continue safely. Use {"kind":"retryable_failure","reason":"..."} only when the current observation is insufficient and another observation may help.

    Coordinates are screen coordinates inside the observed window bounds. Use an accessibility element index only when that index and action are present in the observation. Never invent a target, element index, or action name. Never type text unless the user's task requires that exact text.
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
    static func render(
        request: ComputerUseModelRequest,
        includeScreenshot: Bool
    ) -> ComputerUseRenderedModelPrompt {
        let observation = request.observation
        let target = observation.target
        let window = target.window
        let elements = observation.accessibility.elements
            .map(renderElement)
            .joined(separator: "\n")
        let actionResults = request.recentActionResults
            .map { "- \($0.action.summary) at \($0.completedAt.ISO8601Format())" }
            .joined(separator: "\n")
        let failures = request.recentFailureMessages
            .map { "- \($0)" }
            .joined(separator: "\n")

        let text = """
        User task:
        \(request.instruction)

        Observation iteration: \(request.iteration)
        Target application: \(target.application.displayName) (\(target.application.bundleIdentifier))
        Target window: \(window.title ?? "Untitled")
        Window bounds: x=\(window.bounds.x), y=\(window.bounds.y), width=\(window.bounds.width), height=\(window.bounds.height)
        Observation generation: \(observation.generation)

        Accessibility text:
        \(observation.accessibility.text)

        Accessibility elements:
        \(elements.isEmpty ? "(none)" : elements)

        Recent completed actions:
        \(actionResults.isEmpty ? "(none)" : actionResults)

        Recent failures:
        \(failures.isEmpty ? "(none)" : failures)
        """

        return ComputerUseRenderedModelPrompt(
            text: text,
            screenshot: includeScreenshot ? observation.screenshot : nil
        )
    }

    private static func renderElement(_ element: ComputerUseAXElement) -> String {
        var fields = ["[\(element.index)]"]
        if let role = element.role {
            fields.append("role=\(role)")
        }
        if let subrole = element.subrole {
            fields.append("subrole=\(subrole)")
        }
        if let title = element.title {
            fields.append("title=\"\(title)\"")
        }
        if let description = element.description {
            fields.append("description=\"\(description)\"")
        }
        if let value = element.value {
            fields.append("value=\"\(value)\"")
        }
        if let isEnabled = element.isEnabled {
            fields.append("enabled=\(isEnabled)")
        }
        if element.isFocused {
            fields.append("focused=true")
        }
        if element.isSelected {
            fields.append("selected=true")
        }
        if let bounds = element.bounds {
            fields.append(
                "bounds=\(bounds.x),\(bounds.y),\(bounds.width),\(bounds.height)"
            )
        }
        if !element.actions.isEmpty {
            fields.append("actions=\(element.actions.joined(separator: ","))")
        }
        return fields.joined(separator: " ")
    }
}

enum ComputerUseModelDecisionParser {
    static func parse(_ rawResponse: String) throws -> ComputerUseModelDecision {
        let normalized = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ComputerUseModelError.invalidResponse("the response was empty")
        }

        let json = stripMarkdownFence(from: normalized)
        guard let data = json.data(using: .utf8) else {
            throw ComputerUseModelError.invalidResponse("the response was not valid UTF-8 JSON")
        }

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
        guard !lines.isEmpty else {
            return value
        }
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

        let rendered = ComputerUseModelPromptRenderer.render(
            request: request,
            includeScreenshot: configuration.allowsScreenshotUpload
        )
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
