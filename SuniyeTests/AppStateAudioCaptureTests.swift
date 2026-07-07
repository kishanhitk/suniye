import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class AppStateAudioCaptureTests: XCTestCase {
    private func audioRoute(backend: AudioCaptureBackend, fallback: AudioCaptureFallbackReason?) -> AudioRouteSnapshot {
        AudioRouteSnapshot(
            preferredInputDeviceID: nil, effectiveInputDeviceID: "d", effectiveInputName: "Mic",
            inputTransport: .builtIn, outputTransport: .builtIn, inputSampleRate: 16_000,
            inputChannelCount: 1, requestedEchoCancellation: false, effectiveEchoCancellation: false,
            backend: backend, fallbackReason: fallback
        )
    }

    func testAudioBackendUsedEventDerivesRungAndFallback() {
        func decode(_ r: AudioRouteSnapshot) -> (backend: SafeLabel, fell: Bool, rung: Int)? {
            guard case let .audioBackendUsed(backend, fell, rung) = AppState.audioBackendUsedEvent(for: r) else { return nil }
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
        appState.selectedInputDeviceID = "usb-mic"

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)

        XCTAssertEqual(audioCapture.lastPreferredInputDeviceID, "usb-mic")
        XCTAssertEqual(appState.phase, .recording)
    }

    func testUnavailablePreferredInputDeviceIsPreservedAndActionable() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(
                id: "built-in",
                name: "Built-in Microphone",
                isDefault: true,
                transport: .builtIn
            ),
        ]
        audioCapture.routeSnapshotError = AudioCaptureServiceError.preferredDeviceUnavailable
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

        XCTAssertEqual(appState.selectedInputDeviceID, "studio-mic")
        XCTAssertEqual(appState.selectedInputDeviceName, "Studio Microphone")
        XCTAssertEqual(
            appState.availableInputDevices.first(where: { $0.id == "studio-mic" })?.isAvailable,
            false
        )
        XCTAssertEqual(appState.recommendedInputDevice?.id, "built-in")
        XCTAssertEqual(appState.effectiveInputDeviceStatusText, "Studio Microphone is unavailable")
        XCTAssertNotNil(appState.audioRouteWarningText)
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
            fallbackReason: nil
        )
        let settingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            generalSettingsStore: settingsStore
        )

        appState.useRecommendedInputDevice()

        XCTAssertEqual(appState.selectedInputDeviceID, "built-in")
        XCTAssertEqual(settingsStore.latest.preferredInputDeviceName, "Built-in Microphone")
        XCTAssertTrue(appState.audioRouteWarningText?.contains("call-quality") == true)
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
            .listening(levels: Array(repeating: 0.42, count: AudioLevelMeter.bandCount), source: .manual)
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
