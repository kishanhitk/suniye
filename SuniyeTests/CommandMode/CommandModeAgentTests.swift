import XCTest
@testable import Suniye

final class CommandModeAgentTests: XCTestCase {
    /// Thread-safe recorder so test doubles can cross the actor boundary cleanly.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        func add(_ value: String) { lock.lock(); storage.append(value); lock.unlock() }
        var items: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    private final class ScriptedBrain: AgentBrain, @unchecked Sendable {
        private let calls: [ToolCall]
        private let lock = NSLock()
        private var index = 0
        init(_ calls: [ToolCall]) { self.calls = calls }
        func nextToolCall(task: String, observation: String, history: [String], toolNames: [String]) async throws -> ToolCall {
            lock.lock(); defer { index += 1; lock.unlock() }
            return index < calls.count ? calls[index] : ToolCall(name: "finish", arguments: [:])
        }
    }

    private struct RecordingTool: AgentTool {
        let name: String
        let risk: RiskTier
        let terminal: Bool
        let recorder: Recorder
        func execute(_ arguments: [String: String]) async throws -> ToolResult {
            recorder.add(name)
            return ToolResult(output: "did \(name)", isTerminal: terminal)
        }
    }

    private struct FakeScreen: ScreenReading {
        func readScreen() async -> String { "Safari — frontmost" }
    }

    func testRunsToolsThenStopsOnTerminal() async {
        let recorder = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "open_app", risk: .benign, terminal: false, recorder: recorder),
            RecordingTool(name: "finish", risk: .benign, terminal: true, recorder: recorder),
        ])
        let brain = ScriptedBrain([
            ToolCall(name: "open_app", arguments: ["name": "Safari"]),
            ToolCall(name: "finish", arguments: [:]),
        ])
        let agent = CommandModeAgent(brain: brain, registry: registry, screenReader: FakeScreen(), maxSteps: 10)
        _ = await agent.run(task: "open safari")
        XCTAssertEqual(recorder.items, ["open_app", "finish"])
    }

    func testStopsAtStepCap() async {
        let recorder = Recorder()
        let steps = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "open_app", risk: .benign, terminal: false, recorder: recorder),
        ])
        let brain = ScriptedBrain(Array(repeating: ToolCall(name: "open_app", arguments: [:]), count: 100))
        let agent = CommandModeAgent(brain: brain, registry: registry, screenReader: FakeScreen(),
                                     maxSteps: 3, onStep: { _ in steps.add("s") })
        _ = await agent.run(task: "loop")
        XCTAssertLessThanOrEqual(steps.items.count, 3)
    }

    func testUnknownToolIsReportedNotCrashed() async {
        let recorder = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "finish", risk: .benign, terminal: true, recorder: recorder),
        ])
        let brain = ScriptedBrain([ToolCall(name: "bogus", arguments: [:]), ToolCall(name: "finish", arguments: [:])])
        let agent = CommandModeAgent(brain: brain, registry: registry, screenReader: FakeScreen(), maxSteps: 10)
        let summary = await agent.run(task: "x")
        XCTAssertFalse(summary.isEmpty)
    }
}
