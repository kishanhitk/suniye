import XCTest
@testable import Suniye

/// Dictation from the shortcut to the text in the focused field.
@MainActor
final class DictationFlowTests: XCTestCase {
    func testSpeechIsRecognizedOnTheMacAndTypedIntoTheField() async throws {
        let app = try FlowApp(self, speech: .parakeet)
        await app.launch()
        let speech = try await SpokenAudio.sentence("Please schedule the dentist appointment for Tuesday.")

        await app.dictate(speech)

        let typed = app.focusedApp.text
        XCTAssertTrue(typed.lowercased().contains("dentist appointment"), "typed: \(typed)")
        XCTAssertTrue(typed.lowercased().contains("tuesday"), "the last word is kept; typed: \(typed)")
        XCTAssertEqual(app.appState.recentResults.map(\.text), [typed])
        XCTAssertGreaterThan(app.appState.library.stats.lifetimeWords, 0)
    }

    func testNoiseWithoutSpeechIsNeitherTypedNorSaved() async throws {
        let app = try FlowApp(self, speech: .parakeet)
        await app.launch()

        await app.dictate(RoomNoise.make(seconds: 2))

        XCTAssertEqual(app.focusedApp.text, "")
        XCTAssertTrue(app.appState.recentResults.isEmpty)
        let stoppedBySpeechCheck = app.analytics.trackedEvents.contains {
            if case .dictationEmpty(reason: .noSpeech) = $0 { return true }
            return false
        }
        XCTAssertTrue(stoppedBySpeechCheck, "the speech check stops the clip before the engine")
    }

    func testAControlThatIsNotTextKeepsTheClipboardAndPasteLastTypesTheText() async throws {
        let app = try FlowApp(self)
        await app.launch()
        app.focusedApp.setClipboard("what the user copied")
        app.focusedApp.focus = .notText

        await app.dictate(saying: "Hello from the train.")

        XCTAssertEqual(app.focusedApp.text, "")
        XCTAssertEqual(app.focusedApp.clipboard, "what the user copied")
        XCTAssertEqual(app.appState.recentResults.map(\.text), ["Hello from the train."])
        XCTAssertEqual(app.appState.floatingIndicatorState, .error(message: "Couldn't insert text. Focus a text field, then press ⌃⌘V."))

        app.focusedApp.focus = .textField
        app.hotkeys.onPasteLastTranscript?()
        await waitUntil { app.focusedApp.text == "Hello from the train." }

        XCTAssertEqual(app.focusedApp.returnCount, 0)
        XCTAssertEqual(app.appState.recentResults.count, 1)
    }

    func testAutoSubmitPressesReturnOnlyWhenATextFieldTookTheText() async throws {
        var general = GeneralSettings(onboardingProgress: .finished)
        general.autoSubmitEnabled = true
        let app = try FlowApp(self, general: general)
        await app.launch()
        app.focusedApp.setClipboard("what the user copied")

        await app.dictate(saying: "Ship it.")

        XCTAssertEqual(app.focusedApp.text, "Ship it.")
        XCTAssertEqual(app.focusedApp.returnCount, 1)

        app.focusedApp.focus = .coldBrowser
        await app.dictate(saying: "Ship it again.")
        await waitUntil { app.focusedApp.clipboard == "what the user copied" }

        XCTAssertEqual(app.focusedApp.blindPastes, ["Ship it again."])
        XCTAssertEqual(app.focusedApp.returnCount, 1, "Return is withheld when no field can be seen")
    }

    func testWithoutAccessibilityTheTextIsCopiedAndTheSystemAsksOnce() async throws {
        let app = try FlowApp(self)
        app.accessibilityTrusted = false
        await app.launch()

        await app.dictate(saying: "Hello without access.")
        await app.dictate(saying: "Hello without access.")

        XCTAssertEqual(app.accessibilityPromptCount, 1, "the system dialog shows once per launch")
        XCTAssertEqual(app.focusedApp.text, "")
        XCTAssertEqual(app.focusedApp.clipboard, "Hello without access.")
        XCTAssertEqual(app.appState.recentResults.count, 2)
        XCTAssertEqual(app.appState.floatingIndicatorState, .error(message: app.appState.clipboardOnlyNoticeMessage))
        XCTAssertTrue(app.appState.clipboardOnlyNoticeMessage.contains("Not pasted: Accessibility is off."))
    }

    func testReleasingTheShortcutWhileTheMicrophonePromptIsOpenRecordsNothing() async throws {
        let app = try FlowApp(self)
        let prompt = AsyncGate()
        app.micStatus = .notDetermined
        app.micRequest = {
            await prompt.wait()
            return true
        }
        await app.launch()

        app.hotkeys.onHotkeyDown?()
        await drainScheduledTasks()
        app.hotkeys.onHotkeyUp?()
        await drainScheduledTasks()
        app.micStatus = .authorized
        prompt.open()
        await waitUntil { app.appState.floatingIndicatorState == .error(message: "Hold again to dictate") }

        XCTAssertEqual(app.microphone.startCaptureCallCount, 0, "nothing records after the key is up")
        XCTAssertEqual(app.appState.phase, .ready)

        await app.dictate(saying: "Now it works.")
        XCTAssertEqual(app.focusedApp.text, "Now it works.")
    }
}

/// Hands-free dictation from the keyboard: double-tap to lock, Esc to discard.
@MainActor
final class HandsFreeFlowTests: XCTestCase {
    private var app: FlowApp!
    private let firstPress = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        try await super.setUp()
        app = try FlowApp(self)
        await app.launch()
        app.stubEngine.transcribeResult = .success("Hello world.")
    }

    private func press(at milliseconds: Int) async {
        app.now = firstPress.addingTimeInterval(Double(milliseconds) / 1_000)
        app.hotkeys.onHotkeyDown?()
        await drainScheduledTasks()
    }

    private func release(at milliseconds: Int) async {
        app.now = firstPress.addingTimeInterval(Double(milliseconds) / 1_000)
        app.hotkeys.onHotkeyUp?()
        await drainScheduledTasks()
    }

    private func doubleTap() async {
        await press(at: 0)
        await release(at: 120)
        await press(at: 260)
        await release(at: 380)
    }

    func testADoubleTapKeepsRecordingUntilTheNextPressTypesIt() async throws {
        await doubleTap()
        try await Task.sleep(for: .seconds(DictationShortcutGesture.tapInterval + 0.15))
        await drainScheduledTasks()

        XCTAssertEqual(app.appState.phase, .recording, "a locked recording outlives the double-tap window")
        XCTAssertTrue(app.hotkeys.isCancelShortcutEnabled, "Esc can discard the locked recording")

        await press(at: 9_000)
        XCTAssertEqual(app.appState.phase, .recording, "the finishing press waits for its release")
        await release(at: 9_100)
        await waitUntil { self.app.appState.phase == .ready }

        XCTAssertEqual(app.focusedApp.text, "Hello world.")
        XCTAssertFalse(app.hotkeys.isCancelShortcutEnabled, "Esc goes back to the apps")
    }

    func testEscDiscardsALockedRecordingAndTypesNothing() async throws {
        await doubleTap()

        app.hotkeys.onCancel?()
        await waitUntil { self.app.appState.phase == .ready }

        XCTAssertEqual(app.focusedApp.text, "")
        XCTAssertTrue(app.appState.recentResults.isEmpty)
        XCTAssertEqual(app.appState.floatingIndicatorState, .error(message: "Dictation canceled"))
        XCTAssertFalse(app.hotkeys.isCancelShortcutEnabled)
    }
}

/// Steady noise with no voice in it: a fan and a mains hum.
private enum RoomNoise {
    static func make(seconds: Double, sampleRate: Int = 48_000) -> [Float] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        return (0 ..< Int(seconds * Double(sampleRate))).map { index in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let hiss = Float(Int64(bitPattern: state >> 11) % 1_000) / 1_000 * 0.02
            let hum = 0.02 * Float(sin(2 * Double.pi * 50 * Double(index) / Double(sampleRate)))
            return hiss + hum
        }
    }
}
