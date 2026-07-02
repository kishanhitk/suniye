import Carbon
import XCTest
@testable import Suniye

@MainActor
final class AppStateEditModeTests: XCTestCase {
    func testEditModeHotkeyConfigurationPersistsAndRewiresMonitoring() {
        let hotkeyService = StubHotkeyService()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let settingsStore = TestGeneralSettingsStore()

        let appState = makeTestAppState(
            modelManager: modelManager,
            hotkeyService: hotkeyService,
            generalSettingsStore: settingsStore,
            startServices: true
        )

        let editHotkey = HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(controlKey | optionKey))
        appState.editModeHotkeyConfiguration = editHotkey

        XCTAssertEqual(settingsStore.latest.editModeHotkeyConfiguration, editHotkey)
        XCTAssertGreaterThanOrEqual(hotkeyService.startMonitoringCallCount, 2)
        XCTAssertEqual(hotkeyService.lastEditModeConfiguration, editHotkey)

        appState.editModeHotkeyConfiguration = nil

        XCTAssertNil(settingsStore.latest.editModeHotkeyConfiguration)
        XCTAssertNil(hotkeyService.lastEditModeConfiguration)
    }

    func testEditModeHotkeyConfigurationLoadsFromSettings() {
        let editHotkey = HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey | shiftKey))
        let settingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(editModeHotkeyConfiguration: editHotkey)
        )

        let appState = makeTestAppState(generalSettingsStore: settingsStore)

        XCTAssertEqual(appState.editModeHotkeyConfiguration, editHotkey)
    }

    func testEditModeRewritesSelectionAndInsertsResult() async {
        let apple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .success("Hello, how are you?")
        )
        let scenario = makeEditModeScenario(
            selection: "hey how r u",
            instruction: "make this formal",
            applePostProcessor: apple
        )

        await scenario.appState.beginEditModeRecordingFlow()
        XCTAssertEqual(scenario.appState.phase, .recording)
        XCTAssertEqual(
            scenario.appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0, count: AudioLevelMeter.bandCount), source: .editHotkey)
        )

        await scenario.appState.finishEditModeRecording()

        XCTAssertEqual(scenario.textInsertion.insertedTexts, ["Hello, how are you?"])
        XCTAssertEqual(apple.lastGenerateInstructions, EditModePromptBuilder.rewriteSystemPrompt)
        XCTAssertEqual(
            apple.lastGenerateUserText,
            """
            <instruction>
            make this formal
            </instruction>

            <text>
            hey how r u
            </text>
            """
        )
        XCTAssertEqual(scenario.appState.recentResults.first?.text, "Hello, how are you?")
        XCTAssertEqual(scenario.appState.recentResults.first?.wasLLMPolished, true)
        XCTAssertEqual(scenario.appState.phase, .ready)
        XCTAssertEqual(scenario.appState.floatingIndicatorState, .idle)
        XCTAssertNil(scenario.appState.lastError)
    }

    func testEditModeWithoutSelectionUsesWriteModePrompt() async {
        let apple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .success("Thanks, I will pass this time.")
        )
        let scenario = makeEditModeScenario(
            selection: nil,
            instruction: "write a polite decline",
            applePostProcessor: apple
        )

        await scenario.appState.beginEditModeRecordingFlow()
        await scenario.appState.finishEditModeRecording()

        XCTAssertEqual(scenario.textInsertion.insertedTexts, ["Thanks, I will pass this time."])
        XCTAssertEqual(apple.lastGenerateInstructions, EditModePromptBuilder.writeSystemPrompt)
        XCTAssertEqual(
            apple.lastGenerateUserText,
            """
            <instruction>
            write a polite decline
            </instruction>
            """
        )
        XCTAssertEqual(scenario.appState.phase, .ready)
    }

    func testEditModeBlockedWithoutMagicFormatProvider() async {
        let selectionProvider = StubEditModeSelectionProvider(selection: "hello")
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            editModeSelectionProvider: selectionProvider
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.llmEnabled = false

        await appState.beginEditModeRecordingFlow()

        XCTAssertEqual(audioCapture.startCaptureCallCount, 0)
        XCTAssertEqual(selectionProvider.captureCallCount, 0)
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Set up Magic Format to use Edit Mode"))
        XCTAssertEqual(appState.lastError, "Edit Mode needs a working Magic Format provider")
        XCTAssertEqual(appState.phase, .ready)
    }

    func testEditModeRewriteFailureSurfacesErrorWithoutInsertion() async {
        let apple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .failure(LLMPostProcessorError.timeout)
        )
        let scenario = makeEditModeScenario(
            selection: "hello world",
            instruction: "make this formal",
            applePostProcessor: apple
        )

        await scenario.appState.beginEditModeRecordingFlow()
        await scenario.appState.finishEditModeRecording()

        XCTAssertTrue(scenario.textInsertion.insertedTexts.isEmpty)
        XCTAssertEqual(scenario.appState.floatingIndicatorState, .error(message: "Rewrite failed"))
        XCTAssertTrue(scenario.appState.lastError?.contains("Edit Mode failed") == true)
        XCTAssertEqual(scenario.appState.phase, .ready)
        XCTAssertTrue(scenario.appState.recentResults.isEmpty)
    }

    func testEditModeEmptyInstructionShowsErrorWithoutLLMCall() async {
        let apple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .success("unused")
        )
        let scenario = makeEditModeScenario(
            selection: "hello world",
            instruction: "",
            applePostProcessor: apple
        )

        await scenario.appState.beginEditModeRecordingFlow()
        await scenario.appState.finishEditModeRecording()

        XCTAssertEqual(apple.callCount, 0)
        XCTAssertTrue(scenario.textInsertion.insertedTexts.isEmpty)
        XCTAssertEqual(scenario.appState.floatingIndicatorState, .error(message: "No instruction heard"))
        XCTAssertEqual(scenario.appState.phase, .ready)
    }

    private struct EditModeScenario {
        let appState: AppState
        let textInsertion: SpyTextInsertionService
        let selectionProvider: StubEditModeSelectionProvider
    }

    private func makeEditModeScenario(
        selection: String?,
        instruction: String,
        applePostProcessor: AppleMagicFormatPostProcessor
    ) -> EditModeScenario {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success(instruction)
        let textInsertion = SpyTextInsertionService()
        let selectionProvider = StubEditModeSelectionProvider(selection: selection)

        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertion,
            editModeSelectionProvider: selectionProvider,
            appleMagicFormatPostProcessor: applePostProcessor
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.llmEnabled = true
        appState.llmProvider = .appleFoundationModels

        return EditModeScenario(
            appState: appState,
            textInsertion: textInsertion,
            selectionProvider: selectionProvider
        )
    }
}
