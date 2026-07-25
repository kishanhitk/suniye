import XCTest
@testable import Suniye

@MainActor
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

    private struct ThrowingBrain: AgentBrain {
        struct Boom: Error {}
        func nextToolCall(task: String, observation: String, history: [String], toolNames: [String]) async throws -> ToolCall {
            throw Boom()
        }
    }

    /// Throws for the first `failuresBeforeSuccess` calls (a transient network
    /// blip / prose reply), then returns a real call — to exercise brain retries.
    private final class FlakyBrain: AgentBrain, @unchecked Sendable {
        private let failuresBeforeSuccess: Int
        private let lock = NSLock()
        private var calls = 0
        struct Boom: Error {}
        init(failuresBeforeSuccess: Int) { self.failuresBeforeSuccess = failuresBeforeSuccess }
        func nextToolCall(task: String, observation: String, history: [String], toolNames: [String]) async throws -> ToolCall {
            lock.lock(); let n = calls; calls += 1; lock.unlock()
            if n < failuresBeforeSuccess { throw Boom() }
            return ToolCall(name: "finish", arguments: [:])
        }
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
        let result = await agent.run(task: "open safari")
        XCTAssertEqual(recorder.items, ["open_app", "finish"])
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertEqual(result.toolInvocations, 2)
        XCTAssertEqual(result.invalidActions, 0)
    }

    func testStopsAtStepCap() async {
        let recorder = Recorder()
        let steps = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "open_app", risk: .benign, terminal: false, recorder: recorder),
        ])
        // Distinct args per step so the repeat-guard never short-circuits the cap.
        let brain = ScriptedBrain((0..<100).map { ToolCall(name: "open_app", arguments: ["n": "\($0)"]) })
        let agent = CommandModeAgent(brain: brain, registry: registry, screenReader: FakeScreen(),
                                     maxSteps: 3, onStep: { _ in steps.add("s") })
        let result = await agent.run(task: "loop")
        XCTAssertLessThanOrEqual(steps.items.count, 3)
        XCTAssertEqual(result.outcome, .stepLimit)
        XCTAssertEqual(result.stepCount, 3)
    }

    func testUnknownToolIsReportedNotCrashed() async {
        let recorder = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "finish", risk: .benign, terminal: true, recorder: recorder),
        ])
        let brain = ScriptedBrain([ToolCall(name: "bogus", arguments: [:]), ToolCall(name: "finish", arguments: [:])])
        let agent = CommandModeAgent(brain: brain, registry: registry, screenReader: FakeScreen(), maxSteps: 10)
        let result = await agent.run(task: "x")
        XCTAssertFalse(result.summary.isEmpty)
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertEqual(result.invalidActions, 1)
    }

    func testCancelBeforeRunYieldsCancelledOutcome() async {
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "finish", risk: .benign, terminal: true, recorder: Recorder()),
        ])
        let agent = CommandModeAgent(brain: ScriptedBrain([]), registry: registry, screenReader: FakeScreen(), maxSteps: 10)
        agent.cancel()
        let result = await agent.run(task: "x")
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertEqual(result.stepCount, 0)
    }

    func testBrainFailureOutcome() async {
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "finish", risk: .benign, terminal: true, recorder: Recorder()),
        ])
        // brainRetryDelay: 0 keeps the give-up path fast; it still exhausts retries.
        let agent = CommandModeAgent(brain: ThrowingBrain(), registry: registry, screenReader: FakeScreen(),
                                     maxSteps: 10, maxBrainAttempts: 3, brainRetryDelay: 0)
        let result = await agent.run(task: "x")
        XCTAssertEqual(result.outcome, .brainFailure)
        XCTAssertEqual(result.invalidActions, 1)
    }

    func testReadOnlyToolMayRepeatBeforeStalling() async {
        // Re-reading a still-loading page is legitimate: identical consecutive
        // read_screen calls are allowed a couple of times, THEN the guard stalls.
        let recorder = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "read_screen", risk: .read, terminal: false, recorder: recorder),
        ])
        let brain = ScriptedBrain(Array(repeating: ToolCall(name: "read_screen", arguments: [:]), count: 10))
        let agent = CommandModeAgent(brain: brain, registry: registry, screenReader: FakeScreen(), maxSteps: 10)
        let result = await agent.run(task: "watch the page")
        XCTAssertEqual(result.outcome, .stalled)
        XCTAssertEqual(recorder.items.count, 3, "first call + 2 allowed repeats, then stall")
    }

    func testRepeatedActionIsNudgedNotDoubleFiredThenStalls() async {
        let recorder = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "open_app", risk: .benign, terminal: false, recorder: recorder),
        ])
        let brain = ScriptedBrain(Array(repeating: ToolCall(name: "open_app", arguments: ["name": "Safari"]), count: 5))
        let agent = CommandModeAgent(brain: brain, registry: registry, screenReader: FakeScreen(), maxSteps: 10)
        let result = await agent.run(task: "open safari")
        XCTAssertEqual(result.outcome, .stalled, "a persistent action loop still stalls")
        XCTAssertEqual(recorder.items.count, 1, "the action must run ONCE — the repeat is dropped, never double-fired")
    }

    func testRepeatedActionRecoversWhenModelChangesCourse() async {
        // Clicks the same element, gets nudged, then finishes — the nudge path
        // must let the model self-correct instead of stalling.
        let recorder = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "click", risk: .risky, terminal: false, recorder: recorder),
            RecordingTool(name: "finish", risk: .benign, terminal: true, recorder: recorder),
        ])
        let brain = ScriptedBrain([
            ToolCall(name: "click", arguments: ["element_id": "e1"]),
            ToolCall(name: "click", arguments: ["element_id": "e1"]), // repeat → nudged, not executed
            ToolCall(name: "finish", arguments: [:]),
        ])
        let agent = CommandModeAgent(brain: brain, registry: registry, screenReader: FakeScreen(), maxSteps: 10)
        let result = await agent.run(task: "click then finish")
        XCTAssertEqual(result.outcome, .completed, "the nudge lets the model recover")
        XCTAssertEqual(recorder.items, ["click", "finish"], "click ran once, the duplicate was dropped")
    }

    func testRetriesTransientBrainFailureThenSucceeds() async {
        let recorder = Recorder()
        let registry = AgentToolRegistry(tools: [
            RecordingTool(name: "finish", risk: .benign, terminal: true, recorder: recorder),
        ])
        // Two transient failures, then a real call — within the 3-attempt budget.
        let agent = CommandModeAgent(brain: FlakyBrain(failuresBeforeSuccess: 2), registry: registry,
                                     screenReader: FakeScreen(), maxSteps: 10, maxBrainAttempts: 3, brainRetryDelay: 0)
        let result = await agent.run(task: "x")
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertEqual(recorder.items, ["finish"])
        XCTAssertEqual(result.invalidActions, 0, "a recovered transient failure is not an invalid action")
    }
}
