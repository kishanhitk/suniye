import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class AppStateAudioCaptureTests: XCTestCase {
    private func audioRoute(
        backend: AudioCaptureBackend,
        fallback: AudioCaptureFallbackReason?,
        standIn: AudioInputStandIn? = nil
    ) -> AudioRouteSnapshot {
        AudioRouteSnapshot(
            preferredInputDeviceID: nil, effectiveInputDeviceID: "d", effectiveInputName: "Mic",
            inputTransport: .builtIn, outputTransport: .builtIn, inputSampleRate: 16_000,
            inputChannelCount: 1, requestedEchoCancellation: false, effectiveEchoCancellation: false,
            backend: backend, fallbackReason: fallback, standIn: standIn
        )
    }

    func testAudioBackendUsedEventNamesTheStandInReasonAndNotTheMicrophone() {
        let standIns: [(AudioInputStandIn, String)] = [
            (.preferredMissing, "preferred_missing"),
            (.offWithLidClosed(name: "MacBook Pro Microphone"), "lid_closed"),
            (.bluetoothDefault(name: "AirPods Pro"), "bluetooth_default"),
        ]
        for (standIn, label) in standIns {
            let props = AppState.audioBackendUsedEvent(
                for: audioRoute(backend: .voiceProcessingEngine, fallback: nil, standIn: standIn)
            ).props
            XCTAssertEqual(props["input_stand_in"], .label(label))
            XCTAssertEqual(Set(props.keys), ["backend", "fallback_occurred", "rung", "input_stand_in"])
        }

        let chosen = AppState.audioBackendUsedEvent(for: audioRoute(backend: .voiceProcessingEngine, fallback: nil)).props
        XCTAssertNil(chosen["input_stand_in"])
    }

    func testAudioBackendUsedEventDerivesRungAndFallback() {
        func decode(_ r: AudioRouteSnapshot) -> (backend: SafeLabel, fell: Bool, rung: Int)? {
            guard case let .audioBackendUsed(backend, fell, rung, _) = AppState.audioBackendUsedEvent(for: r) else { return nil }
            return (backend, fell, rung)
        }
        // Primary rung, no fallback.
        let vpe = decode(audioRoute(backend: .voiceProcessingEngine, fallback: nil))
        XCTAssertEqual(vpe?.backend, SafeLabel("voiceProcessingEngine"))
        XCTAssertEqual(vpe?.fell, false)
        XCTAssertEqual(vpe?.rung, 0)
        // inputOnlyHAL is also a primary rung.
        XCTAssertEqual(decode(audioRoute(backend: .inputOnlyHAL, fallback: nil))?.rung, 0)
        // Bluetooth is an echo-cancellation degrade on rung 0 — NOT a ladder descent.
        let bt = decode(audioRoute(backend: .inputOnlyHAL, fallback: .bluetoothRoute))
        XCTAssertEqual(bt?.fell, false)
        XCTAssertEqual(bt?.rung, 0)
        // A real descent: standardEngine after backendStartFailed → rung 1, fell back.
        let fell = decode(audioRoute(backend: .standardEngine, fallback: .backendStartFailed))
        XCTAssertEqual(fell?.fell, true)
        XCTAssertEqual(fell?.rung, 1)
    }

    func testPreferredInputDevicePassedToCaptureService() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(id: "default-device", name: "MacBook Air Microphone", isDefault: true),
            AudioInputDevice(id: "usb-mic", name: "USB Microphone", isDefault: false),
        ]
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(audioCapture: audioCapture)
        appState.microphone.selectedInputDeviceID = "usb-mic"

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)

        XCTAssertEqual(audioCapture.lastPreferredInputDeviceID, "usb-mic")
        XCTAssertEqual(appState.phase, .recording)
    }

    func testMissingSavedMicrophoneStaysSavedAndSettingsNameTheStandIn() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(id: "built-in", name: "MacBook Pro Microphone", isDefault: true, transport: .builtIn),
        ]
        audioCapture.route = makeRoute(id: "built-in", name: "MacBook Pro Microphone", standIn: .preferredMissing)
        let settingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: "studio-mic",
                preferredInputDeviceName: "Studio Microphone"
            )
        )

        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            generalSettingsStore: settingsStore
        )

        XCTAssertEqual(appState.microphone.selectedInputDeviceID, "studio-mic")
        XCTAssertEqual(
            appState.microphone.availableInputDevices.first(where: { $0.id == "studio-mic" })?.availability,
            .notConnected
        )
        XCTAssertEqual(appState.microphone.activeInputDeviceName, "MacBook Pro Microphone")
        XCTAssertEqual(
            appState.microphone.inputStandInNote,
            "Studio Microphone isn't connected, so Suniye uses MacBook Pro Microphone."
        )
        XCTAssertEqual(appState.microphone.effectiveInputDeviceStatusText, appState.microphone.inputStandInNote)
        XCTAssertNil(appState.microphone.audioRouteWarningText)
    }

    func testStandInNoteNamesTheSkippedMicrophone() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.route = makeRoute(
            id: "built-in",
            name: "MacBook Pro Microphone",
            standIn: .bluetoothDefault(name: "AirPods Pro")
        )
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        XCTAssertEqual(
            appState.microphone.inputStandInNote,
            "AirPods Pro is Bluetooth, so Suniye uses MacBook Pro Microphone."
        )

        audioCapture.route = makeRoute(
            id: "display-mic",
            name: "Studio Display Microphone",
            transport: .usb,
            standIn: .offWithLidClosed(name: "MacBook Pro Microphone")
        )
        appState.microphone.refreshInputDevices()
        XCTAssertEqual(
            appState.microphone.inputStandInNote,
            "MacBook Pro Microphone is off while the lid is closed, so Suniye uses Studio Display Microphone."
        )

        audioCapture.route = makeRoute(id: "built-in", name: "MacBook Pro Microphone", standIn: nil)
        appState.microphone.refreshInputDevices()
        XCTAssertNil(appState.microphone.inputStandInNote)
        XCTAssertEqual(appState.microphone.effectiveInputDeviceStatusText, "Using MacBook Pro Microphone - Built-in")
    }

    func testSettingsSayWhyNoMicrophoneCanRecord() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(
                id: "built-in",
                name: "MacBook Pro Microphone",
                isDefault: true,
                transport: .builtIn,
                availability: .offWithLidClosed
            ),
        ]
        audioCapture.routeSnapshotError = AudioCaptureServiceError.builtInMicrophoneOff

        let appState = makeTestAppState(audioCaptureService: audioCapture)

        XCTAssertNil(appState.microphone.audioRouteSnapshot)
        XCTAssertEqual(
            appState.microphone.effectiveInputDeviceStatusText,
            "The built-in microphone is off while the lid is closed."
        )
        XCTAssertNil(appState.microphone.recommendedInputDevice)
    }

    func testRecommendationSkipsTheMicrophoneTheLidSwitchedOff() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(
                id: "built-in",
                name: "MacBook Pro Microphone",
                isDefault: true,
                transport: .builtIn,
                availability: .offWithLidClosed
            ),
            AudioInputDevice(id: "airpods", name: "AirPods Pro", isDefault: false, transport: .bluetooth),
        ]
        audioCapture.route = makeRoute(
            id: "airpods",
            name: "AirPods Pro",
            transport: .bluetooth,
            standIn: .offWithLidClosed(name: "MacBook Pro Microphone")
        )

        let appState = makeTestAppState(audioCaptureService: audioCapture)

        XCTAssertNotNil(appState.microphone.audioRouteWarningText)
        XCTAssertNil(appState.microphone.recommendedInputDevice)
    }

    func testDeviceChangeDuringDictationKeepsTheRouteItRecordsFrom() async throws {
        let audioCapture = StubAudioCaptureService()
        let started = expectation(description: "capture started")
        let canceled = expectation(description: "capture canceled")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        audioCapture.onCancelCapture = { _ in canceled.fulfill() }
        let appState = readyAppState(audioCapture: audioCapture)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        let sessionID = try XCTUnwrap(audioCapture.lastStartedSessionID)

        // The saved USB microphone comes back; the next dictation will use it.
        audioCapture.route = makeRoute(id: "studio-mic", name: "Studio Microphone", transport: .usb, standIn: nil)
        audioCapture.onEvent?(.devicesChanged(audioCapture.availableDevices))
        await drainScheduledTasks()
        XCTAssertEqual(appState.microphone.activeInputDeviceName, "System Microphone")

        audioCapture.onEvent?(.interrupted(sessionID: sessionID, reason: .inputMuted))
        await fulfillment(of: [canceled], timeout: 1)
        await drainScheduledTasks()
        XCTAssertEqual(appState.microphone.activeInputDeviceName, "Studio Microphone")
    }

    func testRecommendedInputDeviceActionPersistsActualDeviceName() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(
                id: "built-in",
                name: "Built-in Microphone",
                isDefault: false,
                transport: .builtIn
            ),
            AudioInputDevice(
                id: "bluetooth",
                name: "Headset",
                isDefault: true,
                transport: .bluetooth
            ),
        ]
        audioCapture.route = AudioRouteSnapshot(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: "bluetooth",
            effectiveInputName: "Headset",
            inputTransport: .bluetooth,
            outputTransport: .bluetooth,
            inputSampleRate: 16_000,
            inputChannelCount: 1,
            requestedEchoCancellation: false,
            effectiveEchoCancellation: false,
            backend: .inputOnlyHAL,
            fallbackReason: nil,
            standIn: nil
        )
        let settingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            generalSettingsStore: settingsStore
        )

        appState.microphone.useRecommendedInputDevice()

        XCTAssertEqual(appState.microphone.selectedInputDeviceID, "built-in")
        XCTAssertEqual(settingsStore.latest.preferredInputDeviceName, "Built-in Microphone")
        XCTAssertTrue(appState.microphone.audioRouteWarningText?.contains("call-quality") == true)
    }

    func testQuickReleaseDuringCaptureStartStopsTheSameSession() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.suspendsStartCapture = true
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let started = expectation(description: "capture start entered")
        let stopped = expectation(description: "capture stopped")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        audioCapture.onStopCapture = { _ in stopped.fulfill() }
        let appState = readyAppState(audioCapture: audioCapture)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await fulfillment(of: [stopped], timeout: 1)
        audioCapture.resumeStartCapture()
        await drainScheduledTasks()

        XCTAssertEqual(audioCapture.stopCaptureCallCount, 1)
        XCTAssertEqual(audioCapture.lastStoppedSessionID, audioCapture.lastStartedSessionID)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testInvalidCaptureDoesNotReachTranscription() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(
            samples: Array(repeating: 0, count: 1_600),
            sampleRate: 16_000
        )
        let transcriptionService = StubTranscriptionService()
        let started = expectation(description: "capture started")
        let stopped = expectation(description: "capture stopped")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        audioCapture.onStopCapture = { _ in stopped.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcriptionService: transcriptionService
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await fulfillment(of: [stopped], timeout: 1)
        await drainScheduledTasks()

        XCTAssertEqual(transcriptionService.transcribeCallCount, 0)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertTrue(appState.lastError?.contains("No speech was detected") == true)
    }

    func testCaptureInterruptionCancelsSessionAndShowsReason() async throws {
        let audioCapture = StubAudioCaptureService()
        let started = expectation(description: "capture started")
        let canceled = expectation(description: "capture canceled")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        audioCapture.onCancelCapture = { _ in canceled.fulfill() }
        let appState = readyAppState(audioCapture: audioCapture)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        let sessionID = try XCTUnwrap(audioCapture.lastStartedSessionID)
        audioCapture.onEvent?(.interrupted(sessionID: sessionID, reason: .inputMuted))
        await fulfillment(of: [canceled], timeout: 1)
        await drainScheduledTasks()

        XCTAssertEqual(audioCapture.cancelCaptureCallCount, 1)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertTrue(appState.lastError?.contains("microphone is muted") == true)
    }

    func testMaximumDurationInterruptionStopsAndTranscribesCapturedAudio() async throws {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Finished at the limit")
        let started = expectation(description: "capture started")
        let transcribed = expectation(description: "audio transcribed")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        transcriptionService.onTranscribe = { transcribed.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcriptionService: transcriptionService
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        let sessionID = try XCTUnwrap(audioCapture.lastStartedSessionID)
        audioCapture.onEvent?(.interrupted(sessionID: sessionID, reason: .maximumDurationReached))
        await fulfillment(of: [transcribed], timeout: 1)
        await drainScheduledTasks()

        XCTAssertEqual(audioCapture.stopCaptureCallCount, 1)
        XCTAssertEqual(audioCapture.cancelCaptureCallCount, 0)
        XCTAssertEqual(transcriptionService.transcribeCallCount, 1)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testSystemLifecycleForwardsToAudioService() async {
        let audioCapture = StubAudioCaptureService()
        let slept = expectation(description: "sleep forwarded")
        let woke = expectation(description: "wake forwarded")
        audioCapture.onSystemSleep = { slept.fulfill() }
        audioCapture.onSystemWake = { woke.fulfill() }
        let appState = makeTestAppState(audioCaptureService: audioCapture)

        await appState.handleSystemWillSleep()
        appState.handleSystemDidWake()
        await fulfillment(of: [slept, woke], timeout: 1)

        XCTAssertEqual(audioCapture.handleSystemSleepCallCount, 1)
        XCTAssertEqual(audioCapture.handleSystemWakeCallCount, 1)
    }

    func testEchoCancellationSettingPassedToCaptureService() async {
        let audioCapture = StubAudioCaptureService()
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(audioCapture: audioCapture)
        appState.echoCancellationEnabled = true

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)

        XCTAssertEqual(audioCapture.lastEchoCancellationEnabled, true)
        XCTAssertEqual(appState.phase, .recording)
    }

    func testAudioLevelEventUpdatesListeningIndicator() async throws {
        let audioCapture = StubAudioCaptureService()
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(audioCapture: audioCapture)

        appState.toggleFloatingIndicatorRecording()
        await fulfillment(of: [started], timeout: 1)
        let sessionID = try XCTUnwrap(audioCapture.lastStartedSessionID)
        audioCapture.onEvent?(.levelsUpdated(
            sessionID: sessionID,
            levels: Array(repeating: 0.42, count: AudioLevelMeter.bandCount)
        ))
        await drainScheduledTasks()

        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0.42, count: AudioLevelMeter.bandCount), source: .manual, preview: .off)
        )
    }

    private func makeRoute(
        id: String,
        name: String,
        transport: AudioDeviceTransport = .builtIn,
        standIn: AudioInputStandIn?
    ) -> AudioRouteSnapshot {
        AudioRouteSnapshot(
            preferredInputDeviceID: nil, effectiveInputDeviceID: id, effectiveInputName: name,
            inputTransport: transport, outputTransport: .builtIn, inputSampleRate: 48_000,
            inputChannelCount: 1, requestedEchoCancellation: false, effectiveEchoCancellation: false,
            backend: .inputOnlyHAL, fallbackReason: nil, standIn: standIn
        )
    }

    private func readyAppState(
        audioCapture: StubAudioCaptureService,
        transcriptionService: StubTranscriptionService = StubTranscriptionService()
    ) -> AppState {
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        return appState
    }

    private func drainScheduledTasks() async {
        for _ in 0 ..< 8 {
            await Task.yield()
        }
    }
}
