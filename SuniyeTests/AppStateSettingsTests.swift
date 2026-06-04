import AppKit
import Carbon
import XCTest
@testable import Suniye

@MainActor
final class AppStateSettingsTests: XCTestCase {
    func testHistoryLoadRecomputesStats() {
        let historyStore = TestHistoryStore()
        historyStore.value = [
            RecentResult(id: UUID(), text: "hello world", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false),
            RecentResult(id: UUID(), text: "second test clip", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        ]

        let appState = makeTestAppState(historyStore: historyStore)

        XCTAssertEqual(appState.sessionCount, 2)
        XCTAssertEqual(appState.wordsTranscribed, 5)
        XCTAssertEqual(appState.totalDictationSeconds, 4.0, accuracy: 0.001)
    }

    func testDeleteRecentResultUpdatesHistoryAndStats() {
        let first = RecentResult(id: UUID(), text: "hello world", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false)
        let second = RecentResult(id: UUID(), text: "second test clip", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        let historyStore = TestHistoryStore()
        historyStore.value = [first, second]

        let appState = makeTestAppState(historyStore: historyStore)
        appState.deleteRecentResult(first)

        XCTAssertEqual(appState.recentResults.count, 1)
        XCTAssertEqual(appState.sessionCount, 1)
        XCTAssertEqual(appState.wordsTranscribed, 3)
        XCTAssertEqual(historyStore.value.map(\.id), [second.id])
    }

    func testCopyLastTranscriptCopiesNewestHistoryResult() {
        let first = RecentResult(id: UUID(), text: "latest transcript", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false)
        let second = RecentResult(id: UUID(), text: "older transcript", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        let historyStore = TestHistoryStore()
        historyStore.value = [first, second]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)

        let appState = makeTestAppState(historyStore: historyStore)
        let didCopy = appState.copyLastTranscript()

        XCTAssertTrue(didCopy)
        XCTAssertEqual(pasteboard.string(forType: .string), "latest transcript")
    }

    func testCopyLastTranscriptReturnsFalseWhenHistoryIsEmpty() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        let appState = makeTestAppState()

        let didCopy = appState.copyLastTranscript()

        XCTAssertFalse(didCopy)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous clipboard")
    }

    func testAutoSubmitDefaultsOff() {
        let appState = makeTestAppState()
        XCTAssertFalse(appState.autoSubmitEnabled)
    }

    func testSoundFeedbackDefaultsOff() {
        let appState = makeTestAppState()
        XCTAssertFalse(appState.soundFeedbackEnabled)
    }

    func testChangingSoundFeedbackPersistsGeneralSettings() {
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        appState.soundFeedbackEnabled = true

        XCTAssertTrue(generalSettingsStore.latest.soundFeedbackEnabled)
    }

    func testFloatingIndicatorSettingsDefaultToVisibleIdleAndDefaultPlacement() {
        let appState = makeTestAppState()

        XCTAssertFalse(appState.hideFloatingIndicatorWhenIdle)
        XCTAssertNil(appState.floatingIndicatorPlacement)
    }

    func testFloatingIndicatorSettingsLoadFromGeneralSettings() {
        let placement = FloatingIndicatorPlacement(centerXRatio: 0.18, bottomYRatio: 0.22)
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                autoSubmitEnabled: false,
                hotkeyConfiguration: .globe,
                echoCancellationEnabled: false,
                hideFloatingIndicatorWhenIdle: true,
                floatingIndicatorPlacement: placement,
                hasSeenOnboardingWelcome: false,
                hasCompletedCoreOnboarding: false
            )
        )
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        XCTAssertTrue(appState.hideFloatingIndicatorWhenIdle)
        XCTAssertEqual(appState.floatingIndicatorPlacement, placement)
    }

    func testChangingHideFloatingIndicatorWhenIdlePersistsGeneralSettings() {
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        appState.hideFloatingIndicatorWhenIdle = true

        XCTAssertTrue(generalSettingsStore.latest.hideFloatingIndicatorWhenIdle)
    }

    func testResetFloatingIndicatorPlacementClearsSavedPlacement() {
        let placement = FloatingIndicatorPlacement(centerXRatio: 0.33, bottomYRatio: 0.18)
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(floatingIndicatorPlacement: placement)
        )
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        appState.resetFloatingIndicatorPlacement()

        XCTAssertNil(appState.floatingIndicatorPlacement)
        XCTAssertNil(generalSettingsStore.latest.floatingIndicatorPlacement)
    }

    func testHandlingFloatingIndicatorPlacementChangePersistsGeneralSettings() {
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)
        let placement = FloatingIndicatorPlacement(centerXRatio: 0.61, bottomYRatio: 0.12)

        appState.handleFloatingIndicatorPlacementChanged(placement)

        XCTAssertEqual(appState.floatingIndicatorPlacement, placement)
        XCTAssertEqual(generalSettingsStore.latest.floatingIndicatorPlacement, placement)
    }

    func testSelectedASRModelPersistsToGeneralSettings() {
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        appState.selectedASRModelID = .senseVoice

        XCTAssertEqual(generalSettingsStore.latest.selectedASRModelID, .senseVoice)
    }

    func testLegacyInstallWithModelInstalledMarksOnboardingComplete() {
        let modelManager = StubModelManager()
        let generalSettingsStore = TestGeneralSettingsStore()

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertTrue(appState.hasSeenOnboardingWelcome)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertEqual(generalSettingsStore.latest.hasSeenOnboardingWelcome, true)
        XCTAssertEqual(generalSettingsStore.latest.hasCompletedCoreOnboarding, true)
    }

    func testFreshInstallStartsAtWelcome() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore()

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertFalse(appState.hasSeenOnboardingWelcome)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
        XCTAssertEqual(generalSettingsStore.latest.hasSeenOnboardingWelcome, false)
        XCTAssertEqual(generalSettingsStore.latest.hasCompletedCoreOnboarding, false)
    }

    func testSeenWelcomeResumesSetup() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false
            )
        )

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .setup)
    }

    func testSetupCompleteRoutesToMagicFormat() {
        let modelManager = StubModelManager()
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false
            )
        )

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .magicFormat)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
    }

    func testOnboardingLocalModelChoiceStartsDownloadAndRoutesToPractice() async {
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)
        appState.hasCompletedCoreOnboarding = false
        appState.activeOnboardingStep = .magicFormat

        appState.confirmMagicFormatDuringOnboarding(.localModel)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(localManager.downloadCallCount, 1)
        XCTAssertTrue(appState.llmEnabled)
        XCTAssertEqual(appState.llmProvider, .localGemma)
        XCTAssertEqual(appState.activeOnboardingStep, .practice)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
    }

    func testOnboardingInstalledLocalModelDoesNotDownloadAgain() {
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let localGemma = NoopLocalGemmaMagicFormatPostProcessor(availability: .available)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: localGemma,
            localLLMModelManager: localManager
        )
        appState.hasCompletedCoreOnboarding = false
        appState.activeOnboardingStep = .magicFormat

        appState.confirmMagicFormatDuringOnboarding(.localModel)

        XCTAssertEqual(localManager.downloadCallCount, 0)
        XCTAssertTrue(appState.llmEnabled)
        XCTAssertEqual(appState.llmProvider, .localGemma)
        XCTAssertEqual(appState.activeOnboardingStep, .practice)
    }

    func testOnboardingInstalledLocalModelWithMissingRuntimeDoesNotAdvance() {
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let localGemma = NoopLocalGemmaMagicFormatPostProcessor(availability: .runtimeUnavailable)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: localGemma,
            localLLMModelManager: localManager
        )
        appState.hasCompletedCoreOnboarding = false
        appState.activeOnboardingStep = .magicFormat

        appState.confirmMagicFormatDuringOnboarding(.localModel)

        XCTAssertFalse(appState.llmEnabled)
        XCTAssertEqual(localManager.downloadCallCount, 0)
        XCTAssertEqual(appState.activeOnboardingStep, .magicFormat)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
    }

    func testOnboardingAppleIntelligenceChoiceEnablesProvider() {
        let apple = NoopAppleMagicFormatPostProcessor(availability: .available)
        let appState = makeTestAppState(appleMagicFormatPostProcessor: apple)
        appState.hasCompletedCoreOnboarding = false
        appState.activeOnboardingStep = .magicFormat

        appState.confirmMagicFormatDuringOnboarding(.appleIntelligence)

        XCTAssertTrue(appState.llmEnabled)
        XCTAssertEqual(appState.llmProvider, .appleFoundationModels)
        XCTAssertEqual(appState.activeOnboardingStep, .practice)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
    }

    func testOnboardingUnavailableAppleIntelligenceDoesNotAdvance() {
        let apple = NoopAppleMagicFormatPostProcessor(availability: .appleIntelligenceNotEnabled)
        let appState = makeTestAppState(appleMagicFormatPostProcessor: apple)
        appState.hasCompletedCoreOnboarding = false
        appState.activeOnboardingStep = .magicFormat

        appState.confirmMagicFormatDuringOnboarding(.appleIntelligence)

        XCTAssertFalse(appState.llmEnabled)
        XCTAssertEqual(appState.activeOnboardingStep, .magicFormat)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
    }

    func testOnboardingUnsupportedLocalModelDoesNotAdvance() {
        let localManager = StubLocalLLMModelManager()
        localManager.isHardwareSupported = false
        let appState = makeTestAppState(localLLMModelManager: localManager)
        appState.hasCompletedCoreOnboarding = false
        appState.activeOnboardingStep = .magicFormat

        appState.confirmMagicFormatDuringOnboarding(.localModel)

        XCTAssertFalse(appState.llmEnabled)
        XCTAssertEqual(localManager.downloadCallCount, 0)
        XCTAssertEqual(appState.activeOnboardingStep, .magicFormat)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
    }

    func testSkippingMagicFormatLeavesItOffAndRoutesToPractice() {
        let appState = makeTestAppState()
        appState.hasCompletedCoreOnboarding = false
        appState.llmEnabled = true
        appState.activeOnboardingStep = .magicFormat

        appState.skipMagicFormatDuringOnboarding()

        XCTAssertFalse(appState.llmEnabled)
        XCTAssertEqual(appState.activeOnboardingStep, .practice)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
    }

    func testLocalModelFailureDoesNotBlockFinishingPractice() {
        let appState = makeTestAppState()
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.localGemmaInstallState = .failed("Network unavailable.")
        appState.activeOnboardingStep = .practice

        XCTAssertEqual(appState.onboardingLocalModelStatusText, "Network unavailable.")

        appState.finishOnboarding()

        XCTAssertNil(appState.activeOnboardingStep)
    }

    func testUnavailableLocalModelStatusAppearsDuringPractice() {
        let appState = makeTestAppState()
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.localGemmaInstallState = .unavailable("Local runtime is missing.")
        appState.activeOnboardingStep = .practice

        XCTAssertEqual(appState.onboardingLocalModelStatusText, "Local runtime is missing.")
    }

    func testOnboardingMagicFormatInitialChoicePrefersLocalModel() {
        let appState = makeTestAppState()

        XCTAssertEqual(OnboardingMagicFormatPresenter(appState: appState).initialProvider, .localModel)
    }

    func testOnboardingMagicFormatInitialChoiceUsesAppleWhenLocalModelUnsupported() {
        let localManager = StubLocalLLMModelManager()
        localManager.isHardwareSupported = false
        let apple = NoopAppleMagicFormatPostProcessor(availability: .available)
        let appState = makeTestAppState(
            appleMagicFormatPostProcessor: apple,
            localLLMModelManager: localManager
        )

        XCTAssertEqual(OnboardingMagicFormatPresenter(appState: appState).initialProvider, .appleIntelligence)
    }

    func testOnboardingMagicFormatUsesAppleWhenInstalledLocalRuntimeIsMissing() throws {
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let localGemma = NoopLocalGemmaMagicFormatPostProcessor(availability: .runtimeUnavailable)
        let apple = NoopAppleMagicFormatPostProcessor(availability: .available)
        let appState = makeTestAppState(
            appleMagicFormatPostProcessor: apple,
            localGemmaMagicFormatPostProcessor: localGemma,
            localLLMModelManager: localManager
        )
        let presenter = OnboardingMagicFormatPresenter(appState: appState)
        let localOption = try XCTUnwrap(presenter.option(for: .localModel))

        XCTAssertFalse(localOption.isSelectable)
        XCTAssertEqual(localOption.unavailableHelpText, "Local model runtime is not available.")
        XCTAssertEqual(localOption.primaryActionTitle, "Local Model Unavailable")
        XCTAssertEqual(presenter.initialProvider, .appleIntelligence)
    }

    func testFinishOnboardingClearsActiveStep() {
        let appState = makeTestAppState()
        appState.activeOnboardingStep = .practice

        appState.finishOnboarding()

        XCTAssertNil(appState.activeOnboardingStep)
    }

    func testOnboardingSetupCompletesOnlyWhenPermissionsAndModelAreReady() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.phase = .ready
        appState.hasMicPermission = true
        XCTAssertFalse(appState.isOnboardingSetupComplete)

        appState.hasAccessibilityPermission = true
        XCTAssertTrue(appState.isOnboardingSetupComplete)
    }

    func testPreferredInputDevicePassedToCaptureService() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(id: "default-device", name: "MacBook Air Microphone", isDefault: true),
            AudioInputDevice(id: "usb-mic", name: "USB Microphone", isDefault: false)
        ]

        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.selectedInputDeviceID = "usb-mic"

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
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
        audioCapture.startCaptureDelayNanoseconds = 150_000_000
        audioCapture.stopCaptureResult = CapturedAudio(
            samples: Array(repeating: 0.2, count: 1_600),
            sampleRate: 16_000
        )
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 20_000_000)
        appState.stopRecordingFromUI()
        try? await Task.sleep(nanoseconds: 260_000_000)

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
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.stopRecordingFromUI()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(transcriptionService.transcribeCallCount, 0)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertTrue(appState.lastError?.contains("No speech was detected") == true)
    }

    func testCaptureInterruptionCancelsSessionAndShowsReason() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)
        if let sessionID = audioCapture.lastStartedSessionID {
            audioCapture.onCaptureInterrupted?(sessionID, .inputMuted)
        } else {
            XCTFail("Expected an active audio session")
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(audioCapture.cancelCaptureCallCount, 1)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertTrue(appState.lastError?.contains("microphone is muted") == true)
    }

    func testMaximumDurationInterruptionStopsAndTranscribesCapturedAudio() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(
            samples: Array(repeating: 0.2, count: 1_600),
            sampleRate: 16_000,
            outcome: .complete
        )
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Finished at the limit")
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)
        if let sessionID = audioCapture.lastStartedSessionID {
            audioCapture.onCaptureInterrupted?(sessionID, .maximumDurationReached)
        } else {
            XCTFail("Expected an active audio session")
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(audioCapture.stopCaptureCallCount, 1)
        XCTAssertEqual(audioCapture.cancelCaptureCallCount, 0)
        XCTAssertEqual(transcriptionService.transcribeCallCount, 1)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testSystemLifecycleForwardsToAudioService() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)

        await appState.handleSystemWillSleep()
        appState.handleSystemDidWake()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.handleSystemSleepCallCount, 1)
        XCTAssertEqual(audioCapture.handleSystemWakeCallCount, 1)
    }

    func testEchoCancellationSettingPassedToCaptureService() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.echoCancellationEnabled = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertEqual(audioCapture.lastEchoCancellationEnabled, true)
        XCTAssertEqual(appState.phase, .recording)
    }

    func testSoundFeedbackDisabledDoesNotPlayRecordingStartSound() async {
        let audioCapture = StubAudioCaptureService()
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertTrue(soundFeedback.playedEvents.isEmpty)
    }

    func testSoundFeedbackEnabledDoesNotPlayAudioThatWouldBeCapturedAtRecordingStart() async {
        let audioCapture = StubAudioCaptureService()
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertTrue(soundFeedback.playedEvents.isEmpty)
    }

    func testSoundFeedbackEnabledDoesNotPlayRecordingStartWhenCaptureFails() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.startCaptureError = FakeError(message: "mic unavailable")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testStartRecordingClearsRetryableTranscriptionError() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .error
        appState.statusText = "Transcription error"
        appState.lastError = "Transcription failed: No audio captured"
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertEqual(appState.phase, .recording)
        XCTAssertEqual(appState.statusText, "Recording")
        XCTAssertNil(appState.lastError)
    }

    func testStartRecordingDoesNotClearNonRetryableLoadError() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .error
        appState.statusText = "Load failed"
        appState.lastError = "Model load failed: broken recognizer"
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 0)
        XCTAssertEqual(appState.phase, .error)
        XCTAssertEqual(appState.statusText, "Load failed")
        XCTAssertEqual(appState.lastError, "Model load failed: broken recognizer")
    }

    func testManualIndicatorToggleStartsRecordingFromReady() async {
        let appState = makeTestAppState()
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.phase, .recording)
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0, count: 12), source: .manual)
        )
    }

    func testManualIndicatorToggleStopsRecordingAndReturnsIndicatorToIdle() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testSuccessfulTranscriptionClearsStaleLastError() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello")
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.lastError = "Transcription failed: previous error"

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testSoundFeedbackEnabledPlaysSuccessForCompletedDictation() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.transcriptionSucceeded])
    }

    func testSoundFeedbackEnabledPlaysSuccessForSubmitOnlyCommand() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("send")
        let textInsertionService = SpyTextInsertionService()
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(textInsertionService.submitCallCount, 1)
        XCTAssertEqual(soundFeedback.playedEvents, [.transcriptionSucceeded])
    }

    func testSoundFeedbackEnabledPlaysErrorForInsertionFailure() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello")
        let textInsertionService = SpyTextInsertionService()
        textInsertionService.insertError = FakeError(message: "paste failed")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testSoundFeedbackEnabledPlaysErrorForTranscriptionFailure() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .failure(FakeError(message: "decoder failed"))
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testSoundFeedbackEnabledPlaysErrorForEmptyNoSubmitTranscription() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testSoundFeedbackEnabledPlaysErrorForEmptyPracticeTranscription() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true
        appState.activeOnboardingStep = .practice

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.stopRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testPracticeModeStoresPreviewWithoutInsertionOrHistory() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello from practice")
        let textInsertionService = SpyTextInsertionService()
        let historyStore = TestHistoryStore()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .practice

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.stopRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "Hello from practice")
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .success)
        XCTAssertTrue(textInsertionService.insertedTexts.isEmpty)
        XCTAssertEqual(textInsertionService.submitCallCount, 0)
        XCTAssertTrue(appState.recentResults.isEmpty)
        XCTAssertTrue(historyStore.value.isEmpty)
    }

    func testPracticeModeFailureClearsStalePreview() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000, outcome: .complete)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .failure(FakeError(message: "decoder failed"))
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .practice
        appState.onboardingPracticeText = "Old preview"
        appState.onboardingPracticeResult = OnboardingPracticeResult(
            message: "Captured locally. You can finish onboarding whenever you're ready.",
            severity: .success
        )

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertNil(appState.onboardingPracticeResult)

        appState.stopRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .error)
        XCTAssertEqual(appState.onboardingPracticeResult?.message, "decoder failed")
    }

    func testRecordingDoesNotStartWhileSetupStepIsActive() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .setup

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 0)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Finish setup first"))
    }

    func testRecordingDoesNotStartWhileMagicFormatStepIsActive() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .magicFormat

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 0)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Finish setup first"))
    }

    func testBlockedIndicatorToggleShowsInlineErrorWhenModelMissing() async {
        let appState = makeTestAppState()
        appState.phase = .needsModel

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Download model first"))
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testBlockedIndicatorToggleDuringTranscribingRestoresProcessingState() async {
        let appState = makeTestAppState()
        appState.phase = .transcribing
        appState.floatingIndicatorState = .processing()

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Still processing previous clip"))
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(appState.floatingIndicatorState, .processing())
    }

    func testAudioLevelCallbackUpdatesListeningIndicator() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        if let sessionID = audioCapture.lastStartedSessionID {
            audioCapture.onLevelsUpdate?(sessionID, Array(repeating: 0.42, count: 12))
        } else {
            XCTFail("Expected an active audio session")
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0.42, count: 12), source: .manual)
        )
    }

    func testChangingHotkeyRewiresMonitoringWhenRuntimeServicesEnabled() {
        let hotkeyService = StubHotkeyService()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []

        let appState = makeTestAppState(
            modelManager: modelManager,
            hotkeyService: hotkeyService,
            startServices: true
        )

        appState.hotkeyConfiguration = .keyCombo(keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: 0)

        XCTAssertGreaterThanOrEqual(hotkeyService.startMonitoringCallCount, 2)
        XCTAssertEqual(hotkeyService.lastConfiguration, .keyCombo(keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: 0))
    }

    func testHotkeyCallbacksStillDriveRecordingWhenRuntimeServicesEnabled() async {
        let hotkeyService = StubHotkeyService()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.2, 0.1], sampleRate: 16_000, outcome: .complete)
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            hotkeyService: hotkeyService,
            startServices: true
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.hasSeenOnboardingWelcome = true
        appState.hasCompletedCoreOnboarding = true
        appState.activeOnboardingStep = nil
        appState.phase = .ready

        hotkeyService.onHotkeyDown?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0, count: 12), source: .hotkey)
        )

        hotkeyService.onHotkeyUp?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testDeleteModelTransitionsToNeedsModel() async {
        let modelManager = StubModelManager()
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready
        appState.hasSeenOnboardingWelcome = true
        appState.hasCompletedCoreOnboarding = true

        appState.deleteModel()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.deleteCallCount, 1)
        XCTAssertEqual(transcriptionService.unloadCallCount, 1)
        XCTAssertEqual(appState.phase, .needsModel)
        XCTAssertEqual(appState.statusText, "Model required")
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
    }

    func testSelectingInstalledASRModelLoadsRecognizerAndPersistsSelection() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice]
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.selectASRModel(.senseVoice)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.selectedASRModelID, .senseVoice)
        XCTAssertEqual(appState.loadedASRModelID, .senseVoice)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(transcriptionService.loadedConfigs.last?.modelID, .senseVoice)
    }

    func testBootstrapFallsBackToAnotherInstalledModelWhenPreferredLoadFails() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice, .moonshineBase]
        let transcriptionService = StubTranscriptionService()
        transcriptionService.loadModelErrorsByModelID = [
            .parakeetV3: FakeError(message: "selected broken"),
            .senseVoice: FakeError(message: "fallback broken")
        ]
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: true,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            generalSettingsStore: generalSettingsStore
        )

        await appState.bootstrap()

        XCTAssertEqual(appState.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.loadedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(generalSettingsStore.latest.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(transcriptionService.loadedConfigs.map(\.modelID), [.parakeetV3, .senseVoice, .moonshineBase])
    }

    func testDeletingCurrentASRModelFallsBackToInstalledAlternative() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice]
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.deleteASRModel(.parakeetV3)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDeletedModelID, .parakeetV3)
        XCTAssertEqual(appState.selectedASRModelID, .senseVoice)
        XCTAssertEqual(appState.loadedASRModelID, .senseVoice)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testDeletingCurrentASRModelSkipsBrokenFallbackAndPersistsSuccessfulAlternative() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice, .moonshineBase]
        let transcriptionService = StubTranscriptionService()
        transcriptionService.loadModelErrorsByModelID = [
            .senseVoice: FakeError(message: "fallback broken")
        ]
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: true,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            generalSettingsStore: generalSettingsStore
        )
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.deleteASRModel(.parakeetV3)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDeletedModelID, .parakeetV3)
        XCTAssertEqual(appState.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.loadedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(generalSettingsStore.latest.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(transcriptionService.loadedConfigs.map(\.modelID), [.senseVoice, .moonshineBase])
    }

    func testModelDownloadSuccessTransitionsSetupToMagicFormat() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.activeOnboardingStep = .setup
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startModelDownload()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.activeOnboardingStep, .magicFormat)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
    }

    func testOnboardingModelDownloadUsesSelectedASRModel() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.activeOnboardingStep = .setup
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startModelDownload()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDownloadedModelID, .parakeetV3)
    }

    func testModelDownloadDerivedUIStateWhileDownloading() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let now = Date(timeIntervalSince1970: 600)
        let appState = makeTestAppState(
            modelManager: modelManager,
            nowProvider: { now }
        )
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .parakeetV3
        appState.downloadProgress = 0.25
        appState.modelDownloadStartedAt = Date(timeIntervalSince1970: 540)

        XCTAssertEqual(appState.modelStatusValue, "Downloading 25%")
        XCTAssertEqual(appState.modelStatusIcon, "arrow.down.circle.fill")
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Downloading…")
        XCTAssertEqual(appState.modelDownloadProgressLabel, "25% downloaded • 170 MB of ~680 MB\nAbout 3m left")
    }

    func testCurrentModelStaysCurrentWhileAnotherModelDownloads() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.senseVoice]
        let appState = makeTestAppState(modelManager: modelManager)
        appState.selectedASRModelID = .senseVoice
        appState.loadedASRModelID = .senseVoice
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .moonshineBase
        appState.downloadProgress = 0.2

        XCTAssertEqual(appState.modelStatusValue, "Current")
        XCTAssertEqual(appState.modelStatusIcon, "checkmark.circle.fill")
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Current")
    }

    func testModelDownloadProgressLabelShowsEstimatingBeforeETAIsKnown() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .parakeetV3
        appState.downloadProgress = 0

        XCTAssertEqual(appState.modelDownloadProgressLabel, "0% downloaded • Zero KB of ~680 MB\nEstimating time remaining")
    }

    func testModelDownloadDerivedUIStateAfterFailure() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .error
        appState.lastFailedASRModelID = .parakeetV3
        appState.lastFailedASRModelError = "network timeout"

        XCTAssertEqual(appState.modelStatusValue, "Download failed")
        XCTAssertEqual(appState.modelStatusIcon, "xmark.octagon.fill")
        XCTAssertEqual(
            appState.modelPrimaryActionDetail,
            "Last attempt failed. Retry setup for Parakeet TDT 0.6B v3 to use it for dictation."
        )
    }

    func testModelOperationStateDuringValidationAfterDownload() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .loading
        appState.activeASRModelOperationID = .parakeetV3

        XCTAssertTrue(appState.isModelOperationInProgress)
        XCTAssertEqual(appState.modelOperationStatusText, "Extracting and validating Parakeet TDT 0.6B v3…")
    }

    func testMissingLibraryModelShowsDownloadActionTitle() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3]
        let appState = makeTestAppState(modelManager: modelManager)
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .whisperLargeV3Turbo), "Download Model")
        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .parakeetV3), "Current")
    }

    func testLaunchAtLoginToggleTracksServiceStatus() {
        let launchService = StubLaunchAtLoginService()
        let appState = makeTestAppState(launchAtLoginService: launchService)

        XCTAssertEqual(appState.launchAtLoginStatus, .disabled)

        appState.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(appState.launchAtLoginStatus, .enabled)
        XCTAssertNil(appState.launchAtLoginError)
    }

    func testLaunchAtLoginToggleSurfacesError() {
        let launchService = StubLaunchAtLoginService()
        launchService.setEnabledError = FakeError(message: "blocked")
        let appState = makeTestAppState(launchAtLoginService: launchService)

        appState.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(appState.launchAtLoginStatus, .disabled)
        XCTAssertEqual(appState.launchAtLoginError, "blocked")
    }

    func testOpenMicrophonePrivacySettingsUsesPrivacyURL() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: {
            openedURLs.append($0)
            return true
        })

        appState.openMicrophonePrivacySettings()

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.absoluteString, "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")
    }

    func testOpenAccessibilityPrivacySettingsUsesPrivacyURL() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: {
            openedURLs.append($0)
            return true
        })

        appState.openAccessibilityPrivacySettings()

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.absoluteString, "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
    }
}
