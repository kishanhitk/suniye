import XCTest
@testable import Suniye

@MainActor
final class AppStateComputerUseVoiceTests: XCTestCase {
    func testDictationSubmitsComputerUseTaskWithoutTextInsertion() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("check the connected Bluetooth devices")
        let insertion = SpyTextInsertionService()
        let handler = SpyComputerUseVoiceTaskHandler()
        let started = expectation(description: "recording started")
        let submitted = expectation(description: "Computer Use task submitted")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        handler.onSubmit = { submitted.fulfill() }

        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            textInsertionService: insertion
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = false
        appState.setComputerUseVoiceTaskHandler(handler)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(handler.instructions, ["check the connected Bluetooth devices"])
        XCTAssertTrue(insertion.insertedTexts.isEmpty)
        XCTAssertTrue(insertion.copiedTexts.isEmpty)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertNil(appState.lastError)
    }

    func testDictationReportsRejectedComputerUseTask() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("try another task")
        let insertion = SpyTextInsertionService()
        let handler = SpyComputerUseVoiceTaskHandler()
        handler.submission = .rejected(message: "Computer Use is already working.")
        let started = expectation(description: "recording started")
        let submitted = expectation(description: "Computer Use task rejected")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        handler.onSubmit = { submitted.fulfill() }

        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            textInsertionService: insertion
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.setComputerUseVoiceTaskHandler(handler)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(handler.instructions, ["try another task"])
        XCTAssertTrue(insertion.insertedTexts.isEmpty)
        XCTAssertTrue(insertion.copiedTexts.isEmpty)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.lastError, "Computer Use is already working.")
    }

    func testEmptyComputerUseTranscriptDoesNotSubmitTask() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("   ")
        let handler = SpyComputerUseVoiceTaskHandler()
        let started = expectation(description: "recording started")
        audioCapture.onStartCapture = { _ in started.fulfill() }

        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.setComputerUseVoiceTaskHandler(handler)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await drainScheduledTasks()

        XCTAssertTrue(handler.instructions.isEmpty)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.lastError, "No Computer Use task was transcribed.")
    }

    func testComputerUseHandlerDisappearingDuringTranscriptionFailsSafely() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("read the current app state")
        let handler = SpyComputerUseVoiceTaskHandler()
        let started = expectation(description: "recording started")
        audioCapture.onStartCapture = { _ in started.fulfill() }

        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.setComputerUseVoiceTaskHandler(handler)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.setComputerUseVoiceTaskHandler(nil)
        appState.stopRecordingFromUI()
        await drainScheduledTasks()

        XCTAssertTrue(handler.instructions.isEmpty)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.lastError, "Computer Use is no longer active.")
    }

    private func drainScheduledTasks() async {
        for _ in 0 ..< 8 {
            await Task.yield()
        }
    }
}

@MainActor
private final class SpyComputerUseVoiceTaskHandler: ComputerUseVoiceTaskHandling {
    private(set) var instructions: [String] = []
    var submission: ComputerUseVoiceTaskSubmission = .started
    var onSubmit: (() -> Void)?

    func submitVoiceTask(_ instruction: String) -> ComputerUseVoiceTaskSubmission {
        instructions.append(instruction)
        onSubmit?()
        return submission
    }
}
