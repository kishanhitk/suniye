import XCTest
@testable import Suniye

@MainActor
final class ComputerUseCoordinatorTests: XCTestCase {
    func testRefreshPublishesPermissionSnapshot() async {
        let permissions = StubComputerUsePermissions(
            snapshots: [
                ComputerUsePermissionSnapshot(
                    accessibility: .granted,
                    screenRecording: .notGranted
                )
            ]
        )
        let coordinator = ComputerUseCoordinator(
            permissions: permissions,
            makeAgent: { _, _ in StubComputerUseAgent() }
        )

        await coordinator.refreshPermissions()

        XCTAssertEqual(coordinator.permissionSnapshot.accessibility, .granted)
        XCTAssertEqual(coordinator.permissionSnapshot.screenRecording, .notGranted)
        XCTAssertEqual(coordinator.phase, .ready)
    }

    func testRequestPermissionRefreshesBothPermissionStates() async {
        let permissions = StubComputerUsePermissions(
            snapshots: [
                ComputerUsePermissionSnapshot(
                    accessibility: .notGranted,
                    screenRecording: .notGranted
                ),
                ComputerUsePermissionSnapshot(
                    accessibility: .granted,
                    screenRecording: .notGranted
                ),
                ComputerUsePermissionSnapshot(
                    accessibility: .granted,
                    screenRecording: .granted
                )
            ]
        )
        let coordinator = ComputerUseCoordinator(
            permissions: permissions,
            makeAgent: { _, _ in StubComputerUseAgent() }
        )

        await coordinator.refreshPermissions()
        await coordinator.requestAccessibility()
        await coordinator.requestScreenRecording()

        XCTAssertEqual(coordinator.permissionSnapshot, .granted)
        let requests = await permissions.requests()
        XCTAssertEqual(requests, [.accessibility, .screenRecording])
    }

    func testSubmittingTaskMovesDraftToConversationAndPublishesAssistantResult() async {
        let agent = StubComputerUseAgent(
            result: ComputerUseAgentResult(outcome: .completed, message: "Battery health is normal.")
        )
        let cursorSession = SpyComputerUseCursorSession()
        let coordinator = readyCoordinator(agent: agent, cursorSession: cursorSession)
        coordinator.draft = "Check my battery health"

        coordinator.submit()

        XCTAssertEqual(coordinator.draft, "")
        XCTAssertEqual(coordinator.conversation.map(\.role), [.user])
        XCTAssertEqual(coordinator.conversation.map(\.text), ["Check my battery health"])
        await waitUntilRunFinishes(coordinator)

        XCTAssertEqual(coordinator.phase, .completed)
        XCTAssertEqual(coordinator.draft, "")
        XCTAssertEqual(
            coordinator.conversation.last,
            ComputerUseConversationMessage(
                id: coordinator.conversation.last?.id ?? UUID(),
                role: .assistant,
                text: "Battery health is normal."
            )
        )
        let tasks = await agent.receivedTasks()
        XCTAssertEqual(tasks.map(\.instruction), ["Check my battery health"])
        XCTAssertEqual(tasks.first?.conversation, [])
        XCTAssertEqual(cursorSession.endSessionCount, 1)
    }

    func testSubmittingTaskPublishesTheDebugSessionIDPassedToTheAgent() async throws {
        let agent = StubComputerUseAgent()
        let coordinator = readyCoordinator(agent: agent)
        coordinator.draft = "Inspect Calculator"

        coordinator.submit()

        let displayedID = try XCTUnwrap(coordinator.debugSessionID)
        await waitUntilRunFinishes(coordinator)
        let tasks = await agent.receivedTasks()
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.debugSessionID, displayedID)
    }

    func testAgentActivitiesAppearInlineBetweenUserAndAssistantMessages() async {
        let activity = ComputerUseActivity(
            toolName: "get_app_state",
            arguments: #"{"app":"Calculator"}"#
        )
        let coordinator = ComputerUseCoordinator(
            permissions: StubComputerUsePermissions(snapshots: []),
            initialPermissionSnapshot: .granted,
            makeAgent: { _, activitySink in
                ActivityEmittingComputerUseAgent(activity: activity, sink: activitySink)
            }
        )
        coordinator.configureModel(testConfiguration)
        coordinator.draft = "Inspect Calculator"

        coordinator.submit()
        await waitUntilRunFinishes(coordinator)

        XCTAssertEqual(coordinator.conversation.map(\.role), [.user, .activity, .assistant])
        XCTAssertEqual(coordinator.conversation[1].activity, activity)
        XCTAssertEqual(coordinator.conversation[2].text, "Done.")
    }

    func testFollowUpPassesPriorConversationWithoutDuplicatingCurrentInstruction() async {
        let agent = StubComputerUseAgent(
            results: [
                ComputerUseAgentResult(outcome: .completed, message: "First answer."),
                ComputerUseAgentResult(outcome: .completed, message: "Second answer.")
            ]
        )
        let coordinator = readyCoordinator(agent: agent)
        coordinator.draft = "First task"
        coordinator.submit()
        await waitUntilRunFinishes(coordinator)
        coordinator.draft = "Follow up"

        coordinator.submit()
        await waitUntilRunFinishes(coordinator)

        let tasks = await agent.receivedTasks()
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(
            tasks[1].conversation.map(\.text),
            ["First task", "First answer."]
        )
        XCTAssertEqual(tasks[1].instruction, "Follow up")
    }

    func testStopInvalidatesRunAndAppendsOneAssistantMessage() async {
        let agent = SuspendedComputerUseAgent()
        let cursorSession = SpyComputerUseCursorSession()
        let coordinator = readyCoordinator(agent: agent, cursorSession: cursorSession)
        coordinator.draft = "Long task"
        coordinator.submit()
        await Task.yield()

        coordinator.stop()
        await agent.finish(
            ComputerUseAgentResult(outcome: .completed, message: "Late result")
        )
        await Task.yield()

        XCTAssertEqual(coordinator.phase, .cancelled)
        XCTAssertEqual(
            coordinator.conversation.map(\.text),
            ["Long task", "Stopped."]
        )
        XCTAssertEqual(coordinator.conversation.map(\.role), [.user, .assistant])
        XCTAssertEqual(cursorSession.endSessionCount, 1)
    }

    func testSubmitRequiresModelAndBothPermissions() {
        let coordinator = ComputerUseCoordinator(
            permissions: StubComputerUsePermissions(snapshots: []),
            makeAgent: { _, _ in StubComputerUseAgent() }
        )
        coordinator.draft = "Do something"

        coordinator.submit()

        XCTAssertEqual(coordinator.phase, .failed)
        XCTAssertEqual(coordinator.errorMessage, "Configure a model before using Computer Use.")
        XCTAssertTrue(coordinator.conversation.isEmpty)
    }

    func testNewConversationClearsTranscriptAndDraft() async {
        let coordinator = readyCoordinator(agent: StubComputerUseAgent())
        coordinator.draft = "Task"
        coordinator.submit()
        await waitUntilRunFinishes(coordinator)
        coordinator.draft = "Unsaved"

        coordinator.startNewConversation()

        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(coordinator.draft, "")
        XCTAssertTrue(coordinator.conversation.isEmpty)
    }

    func testPermissionSettingsRouteThroughInjectedOpener() {
        let opener = SpyComputerUsePermissionSettingsOpener()
        let coordinator = ComputerUseCoordinator(
            permissions: StubComputerUsePermissions(snapshots: []),
            permissionSettings: opener,
            makeAgent: { _, _ in StubComputerUseAgent() }
        )

        coordinator.openPermissionSettings(.accessibility)
        coordinator.openPermissionSettings(.screenRecording)

        XCTAssertEqual(opener.opened, [.accessibility, .screenRecording])
    }

    func testVoiceTaskQueuesUntilPermissionsBecomeReady() async {
        let agent = StubComputerUseAgent()
        let permissions = StubComputerUsePermissions(snapshots: [.granted])
        let coordinator = ComputerUseCoordinator(
            permissions: permissions,
            makeAgent: { _, _ in agent }
        )
        coordinator.configureModel(testConfiguration)

        XCTAssertEqual(coordinator.submitVoiceTask("Check battery health"), .queued)
        XCTAssertTrue(coordinator.isVoiceTaskPending)

        await coordinator.refreshPermissions()
        await waitUntilRunFinishes(coordinator)

        XCTAssertFalse(coordinator.isVoiceTaskPending)
        XCTAssertEqual(coordinator.conversation.map(\.text), ["Check battery health", "Done."])
    }

    private func readyCoordinator(
        agent: some ComputerUseAgentRunning,
        cursorSession: any ComputerUseCursorSessionManaging = NoopComputerUseCursorPresenter()
    ) -> ComputerUseCoordinator {
        let coordinator = ComputerUseCoordinator(
            permissions: StubComputerUsePermissions(snapshots: []),
            initialPermissionSnapshot: .granted,
            cursorSession: cursorSession,
            makeAgent: { _, _ in agent }
        )
        coordinator.configureModel(testConfiguration)
        return coordinator
    }

    private var testConfiguration: ComputerUseRemoteModelConfiguration {
        ComputerUseRemoteModelConfiguration(
            endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
            modelID: "test-model",
            apiKey: "secret"
        )
    }

    private func waitUntilRunFinishes(_ coordinator: ComputerUseCoordinator) async {
        for _ in 0..<100 where coordinator.isRunning {
            await Task.yield()
        }
    }
}

@MainActor
private final class SpyComputerUseCursorSession: ComputerUseCursorSessionManaging {
    private(set) var endSessionCount = 0

    func endSession() {
        endSessionCount += 1
    }
}

private actor StubComputerUseAgent: ComputerUseAgentRunning {
    private var results: [ComputerUseAgentResult]
    private var tasks: [ComputerUseAgentTask] = []

    init(
        result: ComputerUseAgentResult = ComputerUseAgentResult(
            outcome: .completed,
            message: "Done."
        )
    ) {
        results = [result]
    }

    init(results: [ComputerUseAgentResult]) {
        self.results = results
    }

    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        tasks.append(task)
        return results.removeFirst()
    }

    func receivedTasks() -> [ComputerUseAgentTask] {
        tasks
    }
}

private actor SuspendedComputerUseAgent: ComputerUseAgentRunning {
    private var continuation: CheckedContinuation<ComputerUseAgentResult, Never>?

    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(_ result: ComputerUseAgentResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor ActivityEmittingComputerUseAgent: ComputerUseAgentRunning {
    let activity: ComputerUseActivity
    let sink: ComputerUseActivitySink

    init(activity: ComputerUseActivity, sink: ComputerUseActivitySink) {
        self.activity = activity
        self.sink = sink
    }

    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        await sink.emit(activity)
        return ComputerUseAgentResult(outcome: .completed, message: "Done.")
    }
}

private actor StubComputerUsePermissions: ComputerUsePermissionServing {
    private var snapshots: [ComputerUsePermissionSnapshot]
    private var requested: [ComputerUsePermissionKind] = []

    init(snapshots: [ComputerUsePermissionSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() -> ComputerUsePermissionSnapshot {
        snapshots.isEmpty ? .notGranted : snapshots.removeFirst()
    }

    func request(_ permission: ComputerUsePermissionKind) -> ComputerUsePermissionSnapshot {
        requested.append(permission)
        return snapshots.isEmpty ? .notGranted : snapshots.removeFirst()
    }

    func requests() -> [ComputerUsePermissionKind] {
        requested
    }
}

@MainActor
private final class SpyComputerUsePermissionSettingsOpener:
    ComputerUsePermissionSettingsOpening {
    private(set) var opened: [ComputerUsePermissionKind] = []

    func openSettings(for permission: ComputerUsePermissionKind) {
        opened.append(permission)
    }
}
