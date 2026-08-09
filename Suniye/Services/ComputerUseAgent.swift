import Foundation

enum ComputerUseAgentOutcome: Equatable, Sendable {
    case completed
    case cancelled
    case failed
}

struct ComputerUseAgentTask: Equatable, Sendable {
    let instruction: String
    let conversation: [ComputerUseConversationMessage]

    init(
        instruction: String,
        conversation: [ComputerUseConversationMessage] = []
    ) {
        self.instruction = instruction
        self.conversation = conversation
    }
}

struct ComputerUseConversationMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
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

struct ComputerUseAgentResult: Equatable, Sendable {
    let outcome: ComputerUseAgentOutcome
    let message: String
}

protocol ComputerUseAgentRunning: Sendable {
    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult
}

actor ComputerUseAgent: ComputerUseAgentRunning {
    private let model: ComputerUseModelServing
    private let session: ComputerUseSession
    private let screenshots: ComputerUseScreenshotLoading

    init(
        model: ComputerUseModelServing,
        session: ComputerUseSession,
        screenshots: ComputerUseScreenshotLoading = SystemComputerUseScreenshotLoader()
    ) {
        self.model = model
        self.session = session
        self.screenshots = screenshots
    }

    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        let instruction = task.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            return ComputerUseAgentResult(
                outcome: .failed,
                message: "Enter a Computer Use task."
            )
        }

        var messages = task.conversation.map { message in
            ComputerUseModelMessage.text(
                role: message.role == .user ? .user : .assistant,
                text: message.text
            )
        }
        messages.append(.text(role: .user, text: instruction))
        do {
            while true {
                try Task.checkCancellation()
                switch try await model.respond(to: messages) {
                case let .text(text):
                    return ComputerUseAgentResult(outcome: .completed, message: text)
                case let .toolCall(id, name, arguments):
                    messages.append(
                        .toolCall(id: id, name: name, arguments: arguments)
                    )
                    try await execute(
                        id: id,
                        name: name,
                        arguments: arguments,
                        messages: &messages
                    )
                }
            }
        } catch ComputerUseRuntimeError.userIntervened {
            return ComputerUseAgentResult(
                outcome: .cancelled,
                message: ComputerUseRuntimeError.userIntervened.errorDescription ?? "Stopped."
            )
        } catch is CancellationError {
            return ComputerUseAgentResult(outcome: .cancelled, message: "Stopped.")
        } catch {
            return ComputerUseAgentResult(
                outcome: .failed,
                message: localizedMessage(error)
            )
        }
    }

    private func execute(
        id: String,
        name: String,
        arguments: String,
        messages: inout [ComputerUseModelMessage]
    ) async throws {
        do {
            let call = try ComputerUseModelToolCallDecoder.decode(
                name: name,
                arguments: arguments
            )
            let result = try await session.execute(call)
            messages.append(
                .toolResult(id: id, content: try ComputerUseToolResultEncoder.encode(result))
            )
            if case let .appState(state) = result,
               let screenshot = state.screenshot,
               let dataURL = try? await screenshots.dataURL(for: screenshot) {
                messages.append(
                    .image(
                        role: .user,
                        text: "Current \(state.app) screenshot.",
                        dataURL: dataURL
                    )
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ComputerUseRuntimeError {
            throw error
        } catch {
            messages.append(
                .toolResult(
                    id: id,
                    content: try ComputerUseToolResultEncoder.encode(
                        error: localizedMessage(error)
                    )
                )
            )
        }
    }

    private func localizedMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
