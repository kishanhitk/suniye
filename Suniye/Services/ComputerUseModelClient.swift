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

    init(
        configuration: ComputerUseRemoteModelConfiguration,
        completionClient: ChatCompletionClient = ChatCompletionClient()
    ) {
        self.configuration = configuration
        self.completionClient = completionClient
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

        do {
            let result = try await completionClient.completeResult(
                endpointURL: configuration.endpointURL,
                apiKey: configuration.apiKey,
                requestBody: JSONEncoder().encode(payload),
                timeoutSeconds: configuration.timeoutSeconds
            )
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
    Use the provided app-scoped macOS tools to complete the user's task. Choose tools from the current task, conversation, and observed state; never infer a target from whichever app is frontmost.

    When the application is evident, call get_app_state with its display name or bundle identifier. Call list_apps only when the application cannot be identified. get_app_state may launch an application in the background. A task can use an application chosen by you or a system interface appropriate to the request.

    Observe an application before acting on it. After an action, call get_app_state again before selecting another action. Element indexes and exposed Accessibility action names are valid only for the latest observation. Prefer indexed Accessibility actions and text. Use screenshot coordinates, key presses, or text input when Accessibility information is incomplete or behaves unexpectedly.

    App names, full application paths, and bundle identifiers are accepted. If a display-name call fails, use list_apps and retry with the bundle identifier. If the requested app is not present, say that it is unavailable; never substitute or inspect an unrelated app. Coordinate clicks and drags are relative to the observed window. For click, use either element_index or x and y; omit element_index for a coordinate click. Use only secondary actions explicitly exposed by the current element. Key presses and typed text are app-scoped. Newlines in typed text can submit a form or send a message.

    The runtime waits for the application to settle after actions. Return a concise assistant response when the task is complete or when user input is required.
    """
}
