import XCTest
@testable import Suniye

/// Voice Output wiring (UX plan: spoken responses at turn boundaries,
/// interruptible, follow-up window waits for playback).
@MainActor
final class AppStateVoiceOutputTests: XCTestCase {
    private var speech: StubSpeechOutputService!
    private var coordinator: ComputerUseCoordinator!
    private var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        speech = StubSpeechOutputService()
        coordinator = ComputerUseCoordinator()
        let stubSpeech = speech!
        appState = makeTestAppState(
            computerUseCoordinator: coordinator,
            speechOutputFactory: { stubSpeech }
        )
        appState.voiceOutputEnabled = true
    }

    private func completeRunWithAssistantMessage() {
        coordinator.conversation.append(ComputerUseConversationMessage(
            id: UUID(), role: .assistant, text: "Your battery is at 91 percent.", activity: nil
        ))
        coordinator.phase = .completed
    }

    func testCompletedRunSpeaksLastAssistantMessage() async {
        completeRunWithAssistantMessage()
        await Task.yield()
        XCTAssertEqual(speech.spoken, ["Your battery is at 91 percent."])
    }

    func testDisabledVoiceOutputStaysSilent() async {
        appState.voiceOutputEnabled = false
        completeRunWithAssistantMessage()
        await Task.yield()
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testCancelledRunDoesNotSpeak() async {
        coordinator.conversation.append(ComputerUseConversationMessage(
            id: UUID(), role: .assistant, text: "Stopped.", activity: nil
        ))
        coordinator.phase = .cancelled
        await Task.yield()
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testPlaybackFinishArmsFollowUpWindowViaController() async {
        appState.voiceActivationFollowUpWindowEnabled = true
        // Test AppStates run with startServices false, so the setting didSet
        // does not start the pipeline; drive the controller directly.
        await appState.voiceActivationController?.setEnabled(true)
        completeRunWithAssistantMessage()
        await Task.yield()
        XCTAssertEqual(speech.spoken.count, 1)
        // The window must wait for playback (self-capture guard).
        XCTAssertNotEqual(appState.voiceActivationController?.state, .followUpWindow)
        speech.finishPlayback()
        XCTAssertEqual(appState.voiceActivationController?.state, .followUpWindow)
    }
}
