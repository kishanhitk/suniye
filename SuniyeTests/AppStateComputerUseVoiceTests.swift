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
        let handler = SpyComputerUseVoiceTaskHandler()
        let started = expectation(description: "recording started")
        let submitted = expectation(description: "task submitted")
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

    func testRejectedVoiceTaskReportsErrorWithoutInsertion() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("try another task")
        let insertion = SpyTextInsertionService()
        let handler = SpyComputerUseVoiceTaskHandler()
        handler.submission = .rejected(message: "Computer Use is already working.")
        let started = expectation(description: "recording started")
        let submitted = expectation(description: "task rejected")
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

        XCTAssertTrue(insertion.insertedTexts.isEmpty)
        XCTAssertTrue(insertion.copiedTexts.isEmpty)
        XCTAssertEqual(appState.lastError, "Computer Use is already working.")
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
