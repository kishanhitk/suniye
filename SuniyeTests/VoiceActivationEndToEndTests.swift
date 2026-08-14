import XCTest
@testable import Suniye

/// In-process end-to-end pipeline test: real wake-phrase audio drives the
/// production chain — listen-tap frames → resample → real KWS → real VAD →
/// endpointer → transcription → coordinator run → sanitized spoken reply.
/// Only process boundaries are stubbed: the microphone (frames come from a
/// fixture), the ASR model, the remote agent model, and TTS playback. Guards
/// the wiring regressions between components that unit tests cannot see.
@MainActor
final class VoiceActivationEndToEndTests: XCTestCase {
    private var audio: StubAudioCaptureService!
    private var transcription: StubTranscriptionService!
    private var speech: StubSpeechOutputService!
    private var agent: ScriptedComputerUseAgent!
    private var coordinator: ComputerUseCoordinator!
    private var appState: AppState!
    private var wakeSamples: [Float] = []

    override func setUp() async throws {
        try await super.setUp()
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "wake-positive-hey-suniye",
                withExtension: "wav"
            )
        )
        wakeSamples = try WavFixture.pcm16MonoSamples(from: fixture)
        XCTAssertGreaterThan(wakeSamples.count, 8_000)

        audio = StubAudioCaptureService()
        transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("what is on my screen right now")
        speech = StubSpeechOutputService()
        agent = ScriptedComputerUseAgent(message: "**Screen:** you are looking at *Xcode*.")
        let scriptedAgent = agent!
        coordinator = ComputerUseCoordinator(
            permissions: GrantedComputerUsePermissions(),
            initialPermissionSnapshot: .granted,
            makeAgent: { _, _, _ in scriptedAgent }
        )
        coordinator.configureModel(ComputerUseRemoteModelConfiguration(
            endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
            modelID: "test-model",
            apiKey: "secret"
        ))
        let stubSpeech = speech!
        appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audio,
            computerUseCoordinator: coordinator,
            wakeWordDetectorFactory: { try SherpaWakeWordDetector() },
            speechActivityDetectorFactory: { try SileroSpeechActivityDetector() },
            speechOutputFactory: { stubSpeech }
        )
        appState.voiceOutputEnabled = true
        await appState.voiceActivationController?.setEnabled(true)
    }

    func testWakePhraseAudioRunsTaskAndSpeaksSanitizedReply() async throws {
        XCTAssertEqual(appState.voiceActivationController?.state, .ready)

        feed(wakeSamples)
        // Trailing silence lets the final frames decode (chunked model).
        feedSilence(seconds: 1)
        await waitFor("wake detection") {
            if case .listening = self.appState.voiceActivationController?.state {
                return true
            }
            return false
        }

        // The same recording serves as the spoken command; the VAD only needs
        // voiced audio, the words come from the transcription stub.
        feed(wakeSamples)
        feedSilence(seconds: 1.5)
        await waitFor("run completed and reply spoken") {
            !self.coordinator.isRunning && !self.speech.spoken.isEmpty
        }

        let instructions = await agent.receivedInstructions()
        XCTAssertEqual(instructions, ["what is on my screen right now"])
        // Real turn audio reached the transcriber (not an empty buffer).
        XCTAssertGreaterThan(transcription.lastTranscribedSamples.count, 8_000)
        XCTAssertEqual(transcription.transcribePurposes, [.final])
        // The spoken reply is the sanitized agent message, never raw Markdown.
        XCTAssertEqual(speech.spoken, ["Screen: you are looking at Xcode."])
        await waitFor("return to ready") {
            self.appState.voiceActivationController?.state == .ready
        }
    }

    /// Feeds samples through the tap callback in drain-sized 20 ms chunks.
    private func feed(_ samples: [Float]) {
        var index = 0
        while index < samples.count {
            let end = min(index + 320, samples.count)
            audio.listenTapFrames?(Array(samples[index..<end]), 16_000)
            index = end
        }
    }

    private func feedSilence(seconds: Double) {
        let frame = [Float](repeating: 0, count: 320)
        for _ in 0..<Int(seconds / 0.02) {
            audio.listenTapFrames?(frame, 16_000)
        }
    }

    private func waitFor(
        _ description: String,
        timeout: TimeInterval = 5,
        _ check: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if check() {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("timed out waiting for \(description); state=\(String(describing: appState.voiceActivationController?.state)) running=\(coordinator.isRunning) spoken=\(speech.spoken)")
    }
}

private actor ScriptedComputerUseAgent: ComputerUseAgentRunning {
    private let message: String
    private var instructions: [String] = []

    init(message: String) {
        self.message = message
    }

    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        instructions.append(task.instruction)
        return ComputerUseAgentResult(outcome: .completed, message: message)
    }

    func receivedInstructions() -> [String] {
        instructions
    }
}

private actor GrantedComputerUsePermissions: ComputerUsePermissionServing {
    func snapshot() -> ComputerUsePermissionSnapshot { .granted }
    func request(_ permission: ComputerUsePermissionKind) -> ComputerUsePermissionSnapshot {
        .granted
    }
}
