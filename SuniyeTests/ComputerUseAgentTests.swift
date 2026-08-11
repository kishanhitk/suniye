import XCTest
@testable import Suniye

final class ComputerUseAgentTests: XCTestCase {
    func testPublishesOnlyRawToolNameAndArgumentsForEachToolCall() async {
        let model = ScriptedComputerUseModel(
            responses: [
                .toolCall(
                    id: "state-1",
                    name: "get_app_state",
                    arguments: #"{"app":"Calculator"}"#
                ),
                .text("Done."),
            ]
        )
        let recorder = RecordingComputerUseActivitySink()
        let activitySink = ComputerUseActivitySink { activity in
            await recorder.record(activity)
        }
        let agent = ComputerUseAgent(
            model: model,
            session: ComputerUseSession(backend: FreshnessCheckingComputerUseBackend()),
            activitySink: activitySink
        )

        _ = await agent.run(task: ComputerUseAgentTask(instruction: "Inspect Calculator."))

        let activities = await recorder.activities
        XCTAssertEqual(
            activities,
            [
                ComputerUseActivity(
                    toolName: "get_app_state",
                    arguments: #"{"app":"Calculator"}"#
                ),
            ]
        )
    }

    func testEveryLifecycleAndToolLogIncludesTheTaskDebugSessionID() async {
        let model = ScriptedComputerUseModel(
            responses: [
                .toolCall(
                    id: "state-1",
                    name: "get_app_state",
                    arguments: #"{"app":"Calculator"}"#
                ),
                .text("Done."),
            ]
        )
        let logger = RecordingComputerUseLogger()
        let agent = ComputerUseAgent(
            model: model,
            session: ComputerUseSession(backend: FreshnessCheckingComputerUseBackend()),
            logger: logger
        )
        let debugSessionID = ComputerUseDebugSessionID(rawValue: "CU-ABC123DEF456")

        _ = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Inspect Calculator.",
                debugSessionID: debugSessionID
            )
        )

        let messages = logger.messages
        XCTAssertEqual(messages.count, 4)
        XCTAssertTrue(messages.allSatisfy { $0.contains("session=CU-ABC123DEF456") })
        XCTAssertTrue(messages.contains { $0.contains("computer use run started") })
        XCTAssertTrue(messages.contains { $0.contains("computer use tool started") })
        XCTAssertTrue(messages.contains { $0.contains("computer use tool completed") })
        XCTAssertTrue(messages.contains { $0.contains("computer use run completed") })
    }

    func testModelChoosesTheApplicationAndCompletesThroughOrderedToolResults() async {
        let model = ScriptedComputerUseModel(
            responses: [
                .toolCall(
                    id: "state-1",
                    name: "get_app_state",
                    arguments: #"{"app":"Calculator"}"#
                ),
                .toolCall(
                    id: "key-1",
                    name: "press_key",
                    arguments: #"{"app":"Calculator","key":"Return"}"#
                ),
                .text("The Calculator result is 42."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend()
        let agent = ComputerUseAgent(
            model: model,
            session: ComputerUseSession(backend: backend)
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Read the Calculator result.")
        )

        XCTAssertEqual(
            result,
            ComputerUseAgentResult(
                outcome: .completed,
                message: "The Calculator result is 42."
            )
        )
        let calls = await backend.calls
        XCTAssertEqual(calls, [.getAppState, .pressKey])
        let requests = await model.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0], [.text(role: .user, text: "Read the Calculator result.")])
        XCTAssertEqual(requests[1].suffix(2), [
            .toolCall(
                id: "state-1",
                name: "get_app_state",
                arguments: #"{"app":"Calculator"}"#
            ),
            .toolResult(
                id: "state-1",
                content: #"{"app":"Calculator","screenshot":null,"text":"0 AXStaticText: 42"}"#
            ),
        ])
    }

    func testAgentForwardsAFreshObservationBetweenSequentialActions() async {
        let model = ScriptedComputerUseModel(
            responses: [
                .toolCall(
                    id: "state-1",
                    name: "get_app_state",
                    arguments: #"{"app":"Notes"}"#
                ),
                .toolCall(
                    id: "key-1",
                    name: "press_key",
                    arguments: #"{"app":"Notes","key":"Return"}"#
                ),
                .toolCall(
                    id: "state-2",
                    name: "get_app_state",
                    arguments: #"{"app":"Notes"}"#
                ),
                .toolCall(
                    id: "text-1",
                    name: "type_text",
                    arguments: #"{"app":"Notes","text":"hello"}"#
                ),
                .text("Done."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend()
        let agent = ComputerUseAgent(
            model: model,
            session: ComputerUseSession(backend: backend)
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Type hello in Notes.")
        )

        XCTAssertEqual(result.outcome, .completed)
        let calls = await backend.calls
        XCTAssertEqual(calls, [.getAppState, .pressKey, .getAppState, .typeText])
        let requests = await model.requests
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(
            requests[4].suffix(2),
            [
                .toolCall(
                    id: "text-1",
                    name: "type_text",
                    arguments: #"{"app":"Notes","text":"hello"}"#
                ),
                .toolResult(id: "text-1", content: "null"),
            ]
        )
    }

    func testFreshAppStateAddsItsScreenshotAfterTheToolResult() async throws {
        let screenshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("computer-use-agent-\(UUID().uuidString).jpg")
        try Data([1, 2, 3]).write(to: screenshotURL)
        defer { try? FileManager.default.removeItem(at: screenshotURL) }
        let model = ScriptedComputerUseModel(
            responses: [
                .toolCall(
                    id: "state-image",
                    name: "get_app_state",
                    arguments: #"{"app":"Calculator"}"#
                ),
                .text("Done."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend(screenshotURL: screenshotURL)
        let agent = ComputerUseAgent(
            model: model,
            session: ComputerUseSession(backend: backend)
        )

        _ = await agent.run(
            task: ComputerUseAgentTask(instruction: "Inspect Calculator.")
        )

        let requests = await model.requests
        XCTAssertEqual(
            requests[1].last,
            .image(
                role: .user,
                text: "Current Calculator screenshot.",
                dataURL: "data:image/jpeg;base64,AQID"
            )
        )
    }

    func testPriorConversationPrecedesTheCurrentTask() async {
        let model = ScriptedComputerUseModel(responses: [.text("Done.")])
        let agent = ComputerUseAgent(
            model: model,
            session: ComputerUseSession(backend: FreshnessCheckingComputerUseBackend())
        )

        _ = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Now read it.",
                conversation: [
                    ComputerUseConversationMessage(role: .user, text: "Open Calculator."),
                    ComputerUseConversationMessage(
                        activity: ComputerUseActivity(
                            toolName: "get_app_state",
                            arguments: #"{"app":"Calculator"}"#
                        )
                    ),
                    ComputerUseConversationMessage(role: .assistant, text: "Calculator is ready."),
                ]
            )
        )

        let requests = await model.requests
        XCTAssertEqual(
            requests[0],
            [
                .text(role: .user, text: "Open Calculator."),
                .text(role: .assistant, text: "Calculator is ready."),
                .text(role: .user, text: "Now read it."),
            ]
        )
    }

}

private actor RecordingComputerUseActivitySink {
    private(set) var activities: [ComputerUseActivity] = []

    func record(_ activity: ComputerUseActivity) {
        activities.append(activity)
    }
}

private final class RecordingComputerUseLogger: ComputerUseLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    var messages: [String] {
        lock.withLock { recordedMessages }
    }

    func log(_ level: AppLogger.Level, _ message: String) {
        lock.withLock {
            recordedMessages.append(message)
        }
    }
}

private actor ScriptedComputerUseModel: ComputerUseModelServing {
    private var responses: [ComputerUseModelResponse]
    private(set) var requests: [[ComputerUseModelMessage]] = []

    init(responses: [ComputerUseModelResponse]) {
        self.responses = responses
    }

    func respond(to messages: [ComputerUseModelMessage]) async throws -> ComputerUseModelResponse {
        requests.append(messages)
        guard !responses.isEmpty else {
            throw ComputerUseModelError.invalidResponse("no scripted response")
        }
        return responses.removeFirst()
    }
}

private actor FreshnessCheckingComputerUseBackend: ComputerUseToolServing {
    private(set) var calls: [ComputerUseToolName] = []
    private var hasObservedState = false
    private let screenshotURL: URL?

    init(screenshotURL: URL? = nil) {
        self.screenshotURL = screenshotURL
    }

    func listApps() async throws -> [ComputerUseApplication] {
        calls.append(.listApps)
        return []
    }

    func getAppState(app: String, disableDiff: Bool) async throws -> ComputerUseAppState {
        calls.append(.getAppState)
        hasObservedState = true
        return ComputerUseAppState(
            app: app,
            screenshot: screenshotURL,
            text: "0 AXStaticText: 42"
        )
    }

    func click(_ request: ComputerUseClickRequest) async throws {
        try requireObservedState(for: .click)
    }

    func performSecondaryAction(app: String, elementIndex: Int, action: String) async throws {
        try requireObservedState(for: .performSecondaryAction)
    }

    func setValue(app: String, elementIndex: Int, value: String) async throws {
        try requireObservedState(for: .setValue)
    }

    func selectText(
        app: String,
        elementIndex: Int,
        text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType
    ) async throws {
        try requireObservedState(for: .selectText)
    }

    func scroll(
        app: String,
        elementIndex: Int,
        direction: ComputerUseScrollDirection,
        pages: Double
    ) async throws {
        try requireObservedState(for: .scroll)
    }

    func drag(
        app: String,
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double
    ) async throws {
        try requireObservedState(for: .drag)
    }

    func pressKey(app: String, key: String) async throws {
        try requireObservedState(for: .pressKey)
    }

    func typeText(app: String, text: String) async throws {
        try requireObservedState(for: .typeText)
    }

    private func requireObservedState(for call: ComputerUseToolName) throws {
        guard hasObservedState else {
            throw ComputerUseActionError.observationRequired("Calculator")
        }
        hasObservedState = false
        calls.append(call)
    }
}
