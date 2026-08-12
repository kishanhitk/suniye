import XCTest
@testable import Suniye

@MainActor
final class AppStateComputerUseVoiceTests: XCTestCase {
    func testDedicatedHotkeySubmitsRawTaskWithoutComputerUsePageBeingActive() async {
        let hotkeyService = StubHotkeyService()
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("  increase my display brightness  ")
        let insertion = SpyTextInsertionService()
        let agent = VoiceTaskComputerUseAgent()
        let coordinator = makeReadyCoordinator(agent: agent)
        let started = expectation(description: "task recording started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            textInsertionService: insertion,
            hotkeyService: hotkeyService,
            computerUseCoordinator: coordinator,
            micAuthorizationStatusProvider: { .authorized },
            startServices: true
        )
        for _ in 0..<100 where appState.phase == .loading {
            await Task.yield()
        }
        appState.hasMicPermission = true
        appState.phase = .ready

        hotkeyService.onComputerUseHotkeyDown?()
        await fulfillment(of: [started], timeout: 1)
        hotkeyService.onComputerUseHotkeyUp?()
        await waitUntilVoiceTaskFinishes(appState, coordinator: coordinator)

        let receivedTasks = await agent.receivedTasks()
        XCTAssertEqual(receivedTasks.map(\.instruction), ["increase my display brightness"])
        XCTAssertTrue(insertion.insertedTexts.isEmpty)
        XCTAssertTrue(insertion.copiedTexts.isEmpty)
        XCTAssertTrue(appState.recentResults.isEmpty)
    }

    func testEscapeCancelsDedicatedTaskRecordingWithoutSubmittingTranscript() async {
        let hotkeyService = StubHotkeyService()
        let audioCapture = StubAudioCaptureService()
        let agent = VoiceTaskComputerUseAgent()
        let coordinator = makeReadyCoordinator(agent: agent)
        let started = expectation(description: "task recording started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            hotkeyService: hotkeyService,
            computerUseCoordinator: coordinator,
            micAuthorizationStatusProvider: { .authorized },
            startServices: true
        )
        for _ in 0..<100 where appState.phase == .loading {
            await Task.yield()
        }
        appState.hasMicPermission = true
        appState.phase = .ready

        hotkeyService.onComputerUseHotkeyDown?()
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(hotkeyService.onCancel?(), true)
        for _ in 0..<100 where appState.phase != .ready {
            await Task.yield()
        }

        let receivedTasks = await agent.receivedTasks()
        XCTAssertEqual(audioCapture.cancelCaptureCallCount, 1)
        XCTAssertTrue(receivedTasks.isEmpty)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertNil(appState.lastError)
    }

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

    func testVoiceTaskDuringRunBecomesAnInterventionWithoutInsertion() async {
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
        for _ in 0..<100 where appState.phase != .ready {
            await Task.yield()
        }

        XCTAssertTrue(insertion.insertedTexts.isEmpty)
        XCTAssertTrue(insertion.copiedTexts.isEmpty)
        XCTAssertNil(appState.lastError)
        XCTAssertEqual(
            coordinator.conversation.filter { $0.role == .user }.map(\.text),
            ["Existing task", "try another task"]
        )
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

    func testComputerUseRunShowsWorkingIndicatorAndIndicatorTapStopsIt() async {
        let coordinator = makeReadyCoordinator(agent: SuspendedVoiceTaskComputerUseAgent())
        let appState = makeTestAppState(computerUseCoordinator: coordinator)
        appState.phase = .ready
        coordinator.draft = "Long task"

        coordinator.submit()

        XCTAssertEqual(appState.floatingIndicatorState, .computerUseWorking)
        appState.toggleFloatingIndicatorRecording()
        for _ in 0..<100 where coordinator.phase != .cancelled {
            await Task.yield()
        }
        XCTAssertEqual(coordinator.phase, .cancelled)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testComputerUseCompletionShowsCompletedIndicator() async {
        let coordinator = makeReadyCoordinator(agent: VoiceTaskComputerUseAgent())
        let appState = makeTestAppState(computerUseCoordinator: coordinator)
        coordinator.draft = "Check battery"

        coordinator.submit()
        for _ in 0..<100 where coordinator.isRunning {
            await Task.yield()
        }

        XCTAssertEqual(appState.floatingIndicatorState, .computerUseCompleted)
    }

    func testAppLevelNewConversationActionClearsComputerUseSession() async {
        let coordinator = makeReadyCoordinator(agent: VoiceTaskComputerUseAgent())
        let appState = makeTestAppState(computerUseCoordinator: coordinator)
        coordinator.draft = "Check battery"
        coordinator.submit()
        for _ in 0..<100 where coordinator.isRunning {
            await Task.yield()
        }

        appState.startNewComputerUseConversation()

        XCTAssertTrue(coordinator.conversation.isEmpty)
        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testAppLevelNewConversationActionCannotClearAnActiveRun() {
        let coordinator = makeReadyCoordinator(agent: SuspendedVoiceTaskComputerUseAgent())
        let appState = makeTestAppState(computerUseCoordinator: coordinator)
        coordinator.draft = "Long task"
        coordinator.submit()

        appState.startNewComputerUseConversation()

        XCTAssertTrue(coordinator.isRunning)
        XCTAssertFalse(coordinator.conversation.isEmpty)
        XCTAssertEqual(appState.floatingIndicatorState, .computerUseWorking)
        coordinator.stop()
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
