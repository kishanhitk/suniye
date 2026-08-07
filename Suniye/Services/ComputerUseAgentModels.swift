import Foundation

/// Terminal outcome returned by one agent run.
///
/// Intermediate platform and UI states remain owned by the main-actor
/// coordinator. The agent keeps its loop state private to the actor.
enum ComputerUseAgentPhase: String, Codable, Equatable, Sendable {
    case completed
    case askingUser
    case blocked
    case cancelled
    case failed
}

struct ComputerUseAgentTask: Codable, Equatable, Sendable {
    let instruction: String
    let applicationID: String?
    let sessionID: UUID
    let conversation: [ComputerUseConversationMessage]

    init(
        instruction: String,
        applicationID: String? = nil,
        sessionID: UUID = UUID(),
        conversation: [ComputerUseConversationMessage] = []
    ) {
        self.instruction = instruction
        self.applicationID = applicationID
        self.sessionID = sessionID
        self.conversation = conversation
    }
}

struct ComputerUseConversationMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct ComputerUseModelRequest: Codable, Equatable, Sendable {
    let instruction: String
    let observation: ComputerUseObservation
    let observationFreshness: ComputerUseObservationFreshness
    let conversation: [ComputerUseConversationMessage]
    let availableApplications: [ComputerUseApplication]
    let recentActionResults: [ComputerUseActionResult]
    let recentFailureMessages: [String]
    let iteration: Int

    init(
        instruction: String,
        observation: ComputerUseObservation,
        observationFreshness: ComputerUseObservationFreshness = .fresh,
        conversation: [ComputerUseConversationMessage] = [],
        availableApplications: [ComputerUseApplication] = [],
        recentActionResults: [ComputerUseActionResult],
        recentFailureMessages: [String] = [],
        iteration: Int
    ) {
        self.instruction = instruction
        self.observation = observation
        self.observationFreshness = observationFreshness
        self.conversation = conversation
        self.availableApplications = availableApplications
        self.recentActionResults = recentActionResults
        self.recentFailureMessages = recentFailureMessages
        self.iteration = iteration
    }
}

enum ComputerUseObservationFreshness: String, Codable, Equatable, Sendable {
    case fresh
    case stale

    var allowsActions: Bool {
        self == .fresh
    }
}

enum ComputerUseModelDecision: Codable, Equatable, Sendable {
    case action(ComputerUseAction)
    case target(application: String)
    case completed(message: String)
    case askUser(question: String)
    case blocked(reason: String)
    case retryableFailure(reason: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case action
        case message
        case question
        case reason
        case app
    }

    private enum Kind: String, Codable {
        case action
        case target
        case completed
        case askUser = "ask_user"
        case blocked
        case retryableFailure = "retryable_failure"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .action:
            self = .action(try container.decode(ComputerUseAction.self, forKey: .action))
        case .target:
            self = .target(application: try container.decode(String.self, forKey: .app))
        case .completed:
            self = .completed(message: try container.decode(String.self, forKey: .message))
        case .askUser:
            self = .askUser(question: try container.decode(String.self, forKey: .question))
        case .blocked:
            self = .blocked(reason: try container.decode(String.self, forKey: .reason))
        case .retryableFailure:
            self = .retryableFailure(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .action(action):
            try container.encode(Kind.action, forKey: .kind)
            try container.encode(action, forKey: .action)
        case let .target(application):
            try container.encode(Kind.target, forKey: .kind)
            try container.encode(application, forKey: .app)
        case let .completed(message):
            try container.encode(Kind.completed, forKey: .kind)
            try container.encode(message, forKey: .message)
        case let .askUser(question):
            try container.encode(Kind.askUser, forKey: .kind)
            try container.encode(question, forKey: .question)
        case let .blocked(reason):
            try container.encode(Kind.blocked, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case let .retryableFailure(reason):
            try container.encode(Kind.retryableFailure, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }

    var validationMessage: String? {
        switch self {
        case .action:
            return nil
        case let .target(application):
            return Self.nonEmptyMessage(application, label: "target application")
        case let .completed(message):
            return Self.nonEmptyMessage(message, label: "completion message")
        case let .askUser(question):
            return Self.nonEmptyMessage(question, label: "user question")
        case let .blocked(reason):
            return Self.nonEmptyMessage(reason, label: "blocked reason")
        case let .retryableFailure(reason):
            return Self.nonEmptyMessage(reason, label: "retryable failure reason")
        }
    }

    private static func nonEmptyMessage(_ value: String, label: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "The model returned an empty \(label)."
            : nil
    }
}

struct ComputerUseAgentResult: Codable, Equatable, Sendable {
    let phase: ComputerUseAgentPhase
    let message: String
    let question: String?
    let latestObservation: ComputerUseObservation?
    let actionResults: [ComputerUseActionResult]
    let failureCount: Int
}

enum ComputerUseModelError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case invalidResponse(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No Computer Use model is configured."
        case let .invalidResponse(message):
            return "The Computer Use model returned an invalid response: \(message)."
        case let .requestFailed(message):
            return "The Computer Use model request failed: \(message)."
        }
    }
}

protocol ComputerUseModelClient {
    func decide(
        request: ComputerUseModelRequest,
        cancellation: ComputerUseCancellationToken
    ) async throws -> ComputerUseModelDecision
}

struct UnconfiguredComputerUseModelClient: ComputerUseModelClient {
    func decide(
        request: ComputerUseModelRequest,
        cancellation: ComputerUseCancellationToken
    ) async throws -> ComputerUseModelDecision {
        throw ComputerUseModelError.notConfigured
    }
}
