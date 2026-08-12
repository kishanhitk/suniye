import Foundation

enum ComputerUseAgentOutcome: Equatable, Sendable {
    case completed
    case cancelled
    case failed
}

struct ComputerUseDebugSessionID: Equatable, Sendable {
    let rawValue: String

    static func generate(uuid: UUID = UUID()) -> ComputerUseDebugSessionID {
        let compactUUID = uuid.uuidString.replacingOccurrences(of: "-", with: "")
        return ComputerUseDebugSessionID(
            rawValue: "CU-\(compactUUID.prefix(12).uppercased())"
        )
    }
}

struct ComputerUseAgentTask: Equatable, Sendable {
    let instruction: String
    let conversation: [ComputerUseConversationMessage]
    let debugSessionID: ComputerUseDebugSessionID

    init(
        instruction: String,
        conversation: [ComputerUseConversationMessage] = [],
        debugSessionID: ComputerUseDebugSessionID = .generate()
    ) {
        self.instruction = instruction
        self.conversation = conversation
        self.debugSessionID = debugSessionID
    }
}

struct ComputerUseConversationMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
        case activity
    }

    let id: UUID
    let role: Role
    let text: String
    let activity: ComputerUseActivity?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        activity: ComputerUseActivity? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.activity = activity
    }

    init(id: UUID = UUID(), activity: ComputerUseActivity) {
        self.init(
            id: id,
            role: .activity,
            text: "\(activity.toolName)  \(activity.arguments)",
            activity: activity
        )
    }
}

struct ComputerUseAgentResult: Equatable, Sendable {
    let outcome: ComputerUseAgentOutcome
    let message: String
}

protocol ComputerUseAgentRunning: Sendable {
    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult
}

protocol ComputerUseLogging: Sendable {
    func log(_ level: AppLogger.Level, _ message: String)
}

struct SystemComputerUseLogger: ComputerUseLogging {
    func log(_ level: AppLogger.Level, _ message: String) {
        AppLogger.shared.log(level, message)
    }
}

actor ComputerUseAgent: ComputerUseAgentRunning {
    private let model: ComputerUseModelServing
    private let session: ComputerUseSession
    private let screenshots: ComputerUseScreenshotLoading
    private let logger: ComputerUseLogging
    private let activitySink: ComputerUseActivitySink
    private let contextBuilder: ComputerUseModelContextBuilder

    init(
        model: ComputerUseModelServing,
        session: ComputerUseSession,
        screenshots: ComputerUseScreenshotLoading = SystemComputerUseScreenshotLoader(),
        logger: ComputerUseLogging = SystemComputerUseLogger(),
        activitySink: ComputerUseActivitySink = .disabled,
        contextPolicy: ComputerUseModelContextPolicy = .referenceAligned(modelID: "")
    ) {
        self.model = model
        self.session = session
        self.screenshots = screenshots
        self.logger = logger
        self.activitySink = activitySink
        contextBuilder = ComputerUseModelContextBuilder(policy: contextPolicy)
    }

    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        let instruction = task.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            return ComputerUseAgentResult(
                outcome: .failed,
                message: "Enter a Computer Use task."
            )
        }

        let debugSessionID = task.debugSessionID
        var messages = await contextBuilder.initialMessages(
            conversation: task.conversation,
            instruction: instruction,
            screenshots: screenshots
        )
        var step = 0
        log(.info, "computer use run started", session: debugSessionID)
        do {
            while true {
                try Task.checkCancellation()
                messages = contextBuilder.compact(
                    messages,
                    currentInstruction: instruction
                )
                switch try await model.respond(to: messages) {
                case let .text(text):
                    log(
                        .info,
                        "computer use run completed steps=\(step)",
                        session: debugSessionID
                    )
                    return ComputerUseAgentResult(outcome: .completed, message: text)
                case let .toolCall(id, name, arguments):
                    step += 1
                    log(
                        .debug,
                        "computer use tool started step=\(step) name=\(name)",
                        session: debugSessionID
                    )
                    let activity = ComputerUseActivity(
                        toolName: name,
                        arguments: arguments
                    )
                    await activitySink.emit(activity)
                    messages.append(
                        .toolCall(id: id, name: name, arguments: arguments)
                    )
                    try await execute(
                        id: id,
                        name: name,
                        arguments: arguments,
                        activity: activity,
                        debugSessionID: debugSessionID,
                        messages: &messages
                    )
                }
            }
        } catch is CancellationError {
            log(
                .info,
                "computer use run cancelled reason=requested",
                session: debugSessionID
            )
            return ComputerUseAgentResult(outcome: .cancelled, message: "Stopped.")
        } catch {
            log(
                .warning,
                "computer use run failed error_type=\(String(describing: type(of: error)))",
                session: debugSessionID
            )
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
        activity: ComputerUseActivity,
        debugSessionID: ComputerUseDebugSessionID,
        messages: inout [ComputerUseModelMessage]
    ) async throws {
        do {
            let call = try ComputerUseModelToolCallDecoder.decode(
                name: name,
                arguments: arguments
            )
            let result = try await session.execute(call)
            let localResult = try ComputerUseToolResultEncoder.encode(result)
            let modelResult = try ComputerUseModelToolOutput.encode(
                result,
                maximumTokens: contextBuilder.policy.maximumToolOutputTokens
            )
            log(
                .debug,
                "computer use tool completed name=\(name) result=\(result.logValue)",
                session: debugSessionID
            )
            await activitySink.emit(activity.completed(output: localResult))
            messages.append(
                .toolResult(id: id, content: modelResult)
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
            await emitFailure(error, for: activity)
            throw error
        } catch {
            let errorMessage = localizedMessage(error)
            log(
                .warning,
                "computer use tool failed name=\(name) "
                    + "error_type=\(String(describing: type(of: error))) "
                    + "error=\(errorMessage)",
                session: debugSessionID
            )
            let encodedError = try ComputerUseToolResultEncoder.encode(error: errorMessage)
            await activitySink.emit(activity.completed(output: encodedError))
            messages.append(
                .toolResult(
                    id: id,
                    content: encodedError
                )
            )
        }
    }

    private func emitFailure(
        _ error: Error,
        for activity: ComputerUseActivity
    ) async {
        guard let encodedError = try? ComputerUseToolResultEncoder.encode(
            error: localizedMessage(error)
        ) else {
            return
        }
        await activitySink.emit(activity.completed(output: encodedError))
    }

    private func localizedMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func log(
        _ level: AppLogger.Level,
        _ message: String,
        session debugSessionID: ComputerUseDebugSessionID
    ) {
        logger.log(level, "\(message) session=\(debugSessionID.rawValue)")
    }
}

private extension ComputerUseToolResult {
    var logValue: String {
        switch self {
        case let .applications(applications):
            "applications count=\(applications.count)"
        case let .appState(state):
            "app_state text_chars=\(state.text.count) screenshot=\(state.screenshot != nil)"
        case .actionCompleted:
            "action_completed"
        }
    }
}
