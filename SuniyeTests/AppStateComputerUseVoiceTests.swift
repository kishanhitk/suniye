import XCTest
@testable import Suniye

@MainActor
final class AppStateComputerUseVoiceTests: XCTestCase {
    func testDictationSubmitsComputerUseTaskWithoutInsertion() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("check the connected Bluetooth devices")
        let insertion = SpyTextInsertionService()
        let agent = VoiceTaskComputerUseAgent()
        let coordinator = makeReadyCoordinator(agent: agent)
        let started = expectation(description: "recording started")
        audioCapture.onStartCapture = { _ in started.fulfill() }

        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            textInsertionService: insertion,
            computerUseCoordinator: coordinator
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = false
        appState.setComputerUsePageActive(true)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await waitUntilVoiceTaskFinishes(appState, coordinator: coordinator)

        let tasks = await agent.receivedTasks()
        XCTAssertEqual(tasks.map(\.instruction), ["check the connected Bluetooth devices"])
        XCTAssertTrue(insertion.insertedTexts.isEmpty)
        XCTAssertTrue(insertion.copiedTexts.isEmpty)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertNil(appState.lastError)
    }

    func testRejectedVoiceTaskReportsErrorWithoutInsertion() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("try another task")
        let insertion = SpyTextInsertionService()
        let coordinator = makeReadyCoordinator(agent: SuspendedVoiceTaskComputerUseAgent())
        coordinator.draft = "Existing task"
        coordinator.submit()
        let started = expectation(description: "recording started")
        audioCapture.onStartCapture = { _ in started.fulfill() }

        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            textInsertionService: insertion,
            computerUseCoordinator: coordinator
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.setComputerUsePageActive(true)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        for _ in 0..<100 where appState.phase != .error {
            await Task.yield()
        }

        XCTAssertTrue(insertion.insertedTexts.isEmpty)
        XCTAssertTrue(insertion.copiedTexts.isEmpty)
        XCTAssertEqual(appState.lastError, "Computer Use is already working.")
        coordinator.stop()
    }

    func testLeavingComputerUsePageDoesNotCancelQueuedTask() {
        let coordinator = ComputerUseCoordinator(
            permissions: VoiceTaskComputerUsePermissions(),
            initialPermissionSnapshot: .notGranted,
            makeAgent: { _, _ in VoiceTaskComputerUseAgent() }
        )
        coordinator.configureModel(testConfiguration)
        let appState = makeTestAppState(computerUseCoordinator: coordinator)
        appState.setComputerUsePageActive(true)

        XCTAssertEqual(coordinator.submitVoiceTask("Check battery health"), .queued)
        appState.setComputerUsePageActive(false)

        XCTAssertTrue(coordinator.isVoiceTaskPending)
    }

    private func makeReadyCoordinator(
        agent: some ComputerUseAgentRunning
    ) -> ComputerUseCoordinator {
        let coordinator = ComputerUseCoordinator(
            permissions: VoiceTaskComputerUsePermissions(),
            initialPermissionSnapshot: .granted,
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

    private func waitUntilVoiceTaskFinishes(
        _ appState: AppState,
        coordinator: ComputerUseCoordinator
    ) async {
        for _ in 0..<200 where appState.phase != .ready || coordinator.isRunning {
            await Task.yield()
        }
    }
}

private actor VoiceTaskComputerUseAgent: ComputerUseAgentRunning {
    private var tasks: [ComputerUseAgentTask] = []

    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        tasks.append(task)
        return ComputerUseAgentResult(outcome: .completed, message: "Done.")
    }

    func receivedTasks() -> [ComputerUseAgentTask] {
        tasks
    }
}

private actor SuspendedVoiceTaskComputerUseAgent: ComputerUseAgentRunning {
    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        await withTaskCancellationHandler {
            while !Task.isCancelled {
                await Task.yield()
            }
            return ComputerUseAgentResult(outcome: .cancelled, message: "Stopped.")
        } onCancel: {}
    }
}

private actor VoiceTaskComputerUsePermissions: ComputerUsePermissionServing {
    func snapshot() -> ComputerUsePermissionSnapshot { .notGranted }
    func request(_ permission: ComputerUsePermissionKind) -> ComputerUsePermissionSnapshot {
        .notGranted
    }
}
