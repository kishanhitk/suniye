import XCTest
@testable import Suniye

/// End-to-end controller behavior with scripted detectors: tap lifecycle, the
/// wake -> turn -> submit path, and the coexistence rules from the UX plan.
@MainActor
final class VoiceActivationControllerTests: XCTestCase {
    private var audio: StubAudioCaptureService!
    private var transcription: StubTranscriptionService!
    private var wake: StubWakeWordDetector!
    private var speech: StubSpeechActivityDetector!
    private var submitted: [String] = []
    private var submissionResult: ComputerUseVoiceTaskSubmission = .started
    private var runActive = false
    private var wakeCueCount = 0
    private var controller: VoiceActivationController!

    override func setUp() async throws {
        try await super.setUp()
        audio = StubAudioCaptureService()
        transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("check my battery health")
        wake = StubWakeWordDetector()
        speech = StubSpeechActivityDetector()
        submitted = []
        submissionResult = .started
        runActive = false
        wakeCueCount = 0
        controller = VoiceActivationController(
            audioCaptureService: audio,
            transcriptionService: transcription,
            submitVoiceTask: { [weak self] text in
                self?.submitted.append(text)
                return self?.submissionResult ?? .started
            },
            isRunActive: { [weak self] in self?.runActive ?? false },
            playWakeCue: { [weak self] in self?.wakeCueCount += 1 },
            preferredInputDeviceID: { nil },
            echoCancellationEnabled: { false },
            makeWakeDetector: { [wake] in wake! },
            makeSpeechDetector: { [speech] in speech! },
            configuration: .init(
                transcriptFlashSeconds: 0,
                followUpWindowSeconds: 0.15,
                maximumTurnBufferSeconds: 35
            )
        )
    }

    /// Feeds `seconds` of 20 ms frames through the tap callback.
    private func feed(seconds: Double) {
        let frame = [Float](repeating: 0.05, count: 320)
        for _ in 0..<Int(seconds / 0.02) {
            audio.listenTapFrames?(frame, 16_000)
        }
    }

    private func waitForState(
        _ check: @escaping (VoiceActivationState) -> Bool,
        timeout: TimeInterval = 3,
        _ message: String = ""
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if check(controller.state) {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("timed out waiting for state; last=\(controller.state) \(message)")
    }

    func testEnableStartsTapAndWakeStartsListening() async {
        await controller.setEnabled(true)
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(audio.startListenTapCallCount, 1)

        wake.queueWakeHit()
        feed(seconds: 0.1)
        await waitForState { $0 == .listening(.initial) }
        XCTAssertEqual(wakeCueCount, 1)
    }

    func testFullTurnSubmitsTranscript() async {
        await controller.setEnabled(true)
        wake.queueWakeHit()
        feed(seconds: 0.1)
        await waitForState { $0 == .listening(.initial) }

        speech.scheduleSpeech(in: 0.0...1.0)
        feed(seconds: 2.3)
        await waitForState { $0 == .ready }

        XCTAssertEqual(submitted, ["check my battery health"])
    }

    func testSilenceAfterWakeReturnsToReadyWithoutSubmit() async {
        await controller.setEnabled(true)
        wake.queueWakeHit()
        feed(seconds: 0.1)
        await waitForState { $0 == .listening(.initial) }

        feed(seconds: 5.5)
        await waitForState { $0 == .ready }
        XCTAssertTrue(submitted.isEmpty)
    }

    func testRejectedSubmissionEndsInReady() async {
        submissionResult = .rejected(message: "No model")
        await controller.setEnabled(true)
        wake.queueWakeHit()
        feed(seconds: 0.1)
        await waitForState { $0 == .listening(.initial) }
        speech.scheduleSpeech(in: 0.0...1.0)
        feed(seconds: 2.3)
        await waitForState { $0 == .ready }
        XCTAssertEqual(submitted.count, 1)
    }

    func testWakeDuringRunCapturesInterventionContext() async {
        runActive = true
        submissionResult = .intervened
        await controller.setEnabled(true)
        wake.queueWakeHit()
        feed(seconds: 0.1)
        await waitForState { $0 == .listening(.duringRun) }

        speech.scheduleSpeech(in: 0.0...1.0)
        feed(seconds: 2.3)
        await waitForState { $0 == .ready }
        XCTAssertEqual(submitted.count, 1)
    }

    func testSuspendAndResumeAroundCaptureSession() async {
        await controller.setEnabled(true)
        await controller.suspendForCaptureSession()
        XCTAssertEqual(controller.state, .suspended)
        XCTAssertEqual(audio.stopListenTapCallCount, 1)

        await controller.resumeAfterCaptureSession()
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(audio.startListenTapCallCount, 2)
    }

    func testDisableStopsTap() async {
        await controller.setEnabled(true)
        await controller.setEnabled(false)
        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(audio.stopListenTapCallCount, 1)
    }

    func testTapStartFailureSuspends() async {
        audio.startListenTapError = FakeError(message: "tap unavailable")
        await controller.setEnabled(true)
        XCTAssertEqual(controller.state, .suspended)
    }

    // UX plan: follow-up window — speech without a wake phrase submits; the
    // window expires back to Ready.
    func testFollowUpWindowCapturesSpeechWithoutWake() async {
        controller.setFollowUpWindowEnabled(true)
        await controller.setEnabled(true)
        controller.handleRunPhase(.completed)
        XCTAssertEqual(controller.state, .followUpWindow)

        speech.scheduleSpeech(in: 0.0...1.0)
        feed(seconds: 2.3)
        await waitForState { $0 == .ready }
        XCTAssertEqual(submitted.count, 1)
    }

    func testFollowUpWindowExpiresToReady() async {
        controller.setFollowUpWindowEnabled(true)
        await controller.setEnabled(true)
        controller.handleRunPhase(.completed)
        XCTAssertEqual(controller.state, .followUpWindow)
        // Expiry is the endpointer's no-speech timeout on the sample clock:
        // silence past followUpWindowSeconds (0.15 s here) ends the window.
        feed(seconds: 0.5)
        await waitForState { $0 == .ready }
        XCTAssertTrue(submitted.isEmpty)
    }

    func testStoppedRunNeverOpensFollowUpWindow() async {
        controller.setFollowUpWindowEnabled(true)
        await controller.setEnabled(true)
        controller.handleRunPhase(.cancelled)
        XCTAssertEqual(controller.state, .ready)
    }
}
