import XCTest
@testable import Suniye

final class ComputerUseAgentTests: XCTestCase {
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

    func testAgentRejectsASecondActionUntilTheModelGetsFreshState() async {
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
                    id: "text-stale",
                    name: "type_text",
                    arguments: #"{"app":"Notes","text":"hello"}"#
                ),
                .toolCall(
                    id: "state-2",
                    name: "get_app_state",
                    arguments: #"{"app":"Notes"}"#
                ),
                .toolCall(
                    id: "text-fresh",
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
        let staleResult = try? XCTUnwrap(
            requests[3].last
        )
        guard case let .text(errorJSON)? = staleResult?.content else {
            return XCTFail("Expected a tool error result")
        }
        XCTAssertTrue(errorJSON.contains("Observe Calculator before performing an action."))
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
    private var hasFreshState = false
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
        hasFreshState = true
        return ComputerUseAppState(
            app: app,
            screenshot: screenshotURL,
            text: "0 AXStaticText: 42"
        )
    }

    func click(_ request: ComputerUseClickRequest) async throws {
        try consumeFreshState(for: .click)
    }

    func performSecondaryAction(app: String, elementIndex: Int, action: String) async throws {
        try consumeFreshState(for: .performSecondaryAction)
    }

    func setValue(app: String, elementIndex: Int, value: String) async throws {
        try consumeFreshState(for: .setValue)
    }

    func selectText(
        app: String,
        elementIndex: Int,
        text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType
    ) async throws {
        try consumeFreshState(for: .selectText)
    }

    func scroll(
        app: String,
        elementIndex: Int,
        direction: ComputerUseScrollDirection,
        pages: Double
    ) async throws {
        try consumeFreshState(for: .scroll)
    }

    func drag(
        app: String,
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double
    ) async throws {
        try consumeFreshState(for: .drag)
    }

    func pressKey(app: String, key: String) async throws {
        try consumeFreshState(for: .pressKey)
    }

    func typeText(app: String, text: String) async throws {
        try consumeFreshState(for: .typeText)
    }

    private func consumeFreshState(for call: ComputerUseToolName) throws {
        guard hasFreshState else {
            throw ComputerUseActionError.observationRequired("Calculator")
        }
        hasFreshState = false
        calls.append(call)
    }
}
