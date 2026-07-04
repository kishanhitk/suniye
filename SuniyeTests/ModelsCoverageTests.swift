import AppKit
import Carbon
import XCTest
@testable import Suniye

// MARK: - FloatingIndicatorState

final class FloatingIndicatorStateTests: XCTestCase {
    func testLogValueDescribesEveryState() {
        XCTAssertEqual(FloatingIndicatorState.idle.logValue, "idle")
        XCTAssertEqual(FloatingIndicatorState.hover.logValue, "hover")
        XCTAssertEqual(FloatingIndicatorState.listening(levels: [0.2], source: .hotkey).logValue, "listening")
        XCTAssertEqual(FloatingIndicatorState.processing(message: "Formatting…").logValue, "processing")
        XCTAssertEqual(FloatingIndicatorState.error(message: "Boom").logValue, "error")
    }

    func testTracksPointerScreenOnlyWhileIdleOrHovering() {
        XCTAssertTrue(FloatingIndicatorState.idle.tracksPointerScreen)
        XCTAssertTrue(FloatingIndicatorState.hover.tracksPointerScreen)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [], source: .manual).tracksPointerScreen)
        XCTAssertFalse(FloatingIndicatorState.listening(levels: [0.5], source: .editHotkey).tracksPointerScreen)
        XCTAssertFalse(FloatingIndicatorState.processing().tracksPointerScreen)
        XCTAssertFalse(FloatingIndicatorState.error(message: "Boom").tracksPointerScreen)
    }
}

// MARK: - OnboardingModels

final class OnboardingModelsTests: XCTestCase {
    func testStepTitles() {
        XCTAssertEqual(OnboardingStep.welcome.title, "Welcome")
        XCTAssertEqual(OnboardingStep.setup.title, "Set Up")
        XCTAssertEqual(OnboardingStep.magicFormat.title, "Magic Format")
        XCTAssertEqual(OnboardingStep.practice.title, "Try It")
    }

    func testOnboardingProviderMapsToMagicFormatProvider() {
        XCTAssertEqual(OnboardingMagicFormatProvider.localModel.magicFormatProvider, .localGemma)
        XCTAssertEqual(OnboardingMagicFormatProvider.appleIntelligence.magicFormatProvider, .appleFoundationModels)
    }
}

// MARK: - SettingsModels

final class AudioDeviceTransportTests: XCTestCase {
    func testTitles() {
        XCTAssertEqual(AudioDeviceTransport.builtIn.title, "Built-in")
        XCTAssertEqual(AudioDeviceTransport.usb.title, "USB")
        XCTAssertEqual(AudioDeviceTransport.bluetooth.title, "Bluetooth")
        XCTAssertEqual(AudioDeviceTransport.bluetoothLE.title, "Bluetooth LE")
        XCTAssertEqual(AudioDeviceTransport.continuity.title, "Continuity")
        XCTAssertEqual(AudioDeviceTransport.aggregate.title, "Aggregate")
        XCTAssertEqual(AudioDeviceTransport.virtual.title, "Virtual")
        XCTAssertEqual(AudioDeviceTransport.other.title, "Other")
    }

    func testBluetoothClassification() {
        XCTAssertTrue(AudioDeviceTransport.bluetooth.isBluetooth)
        XCTAssertTrue(AudioDeviceTransport.bluetoothLE.isBluetooth)
        XCTAssertFalse(AudioDeviceTransport.builtIn.isBluetooth)
        XCTAssertFalse(AudioDeviceTransport.usb.isBluetooth)
    }

    func testRecommendedPhysicalInputs() {
        XCTAssertTrue(AudioDeviceTransport.builtIn.isRecommendedPhysicalInput)
        XCTAssertTrue(AudioDeviceTransport.usb.isRecommendedPhysicalInput)
        XCTAssertFalse(AudioDeviceTransport.bluetooth.isRecommendedPhysicalInput)
        XCTAssertFalse(AudioDeviceTransport.virtual.isRecommendedPhysicalInput)
    }
}

final class HotkeyConfigurationTests: XCTestCase {
    func testGlobeDisplayAndExampleDescription() {
        XCTAssertEqual(HotkeyConfiguration.globe.displayString, "Globe")
        XCTAssertEqual(HotkeyConfiguration.globe.exampleDescription, "Fn/Globe key (macOS dictation key)")
        XCTAssertEqual(HotkeyConfiguration.globe.modifierLabels, [])
    }

    func testKeyComboDisplayIncludesAllModifierLabelsInOrder() {
        let combo = HotkeyConfiguration.keyCombo(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        )

        XCTAssertEqual(combo.modifierLabels, ["Control", "Option", "Shift", "Command"])
        XCTAssertEqual(combo.displayString, "Control + Option + Shift + Command + A")
        XCTAssertEqual(combo.exampleDescription, combo.displayString)
    }

    func testFromFlagsChangedFunctionKeyEventIsGlobe() throws {
        let event = try XCTUnwrap(makeKeyEvent(type: .flagsChanged, flags: .function, keyCode: UInt16(kVK_Function)))

        XCTAssertEqual(HotkeyConfiguration.from(event: event), .globe)
    }

    func testFromFlagsChangedWithOtherModifiersIsNil() throws {
        let event = try XCTUnwrap(makeKeyEvent(type: .flagsChanged, flags: .shift, keyCode: UInt16(kVK_Shift)))

        XCTAssertNil(HotkeyConfiguration.from(event: event))
    }

    func testFromKeyDownOnBareModifierKeyIsNil() throws {
        let event = try XCTUnwrap(makeKeyEvent(type: .keyDown, flags: [], keyCode: UInt16(kVK_Shift)))

        XCTAssertNil(HotkeyConfiguration.from(event: event))
    }

    func testFromKeyDownProducesKeyCombo() throws {
        let event = try XCTUnwrap(makeKeyEvent(type: .keyDown, flags: [.command, .shift], keyCode: UInt16(kVK_ANSI_A)))

        XCTAssertEqual(
            HotkeyConfiguration.from(event: event),
            .keyCombo(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey))
        )
    }

    func testCarbonModifiersMapsEachFlag() {
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: []), 0)
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: .control), UInt32(controlKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: .option), UInt32(optionKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: .shift), UInt32(shiftKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: .command), UInt32(cmdKey))
        XCTAssertEqual(
            HotkeyConfiguration.carbonModifiers(from: [.control, .option, .shift, .command]),
            UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        )
    }

    func testKeyNameCoversEveryNamedKey() {
        let expectations: [(Int, String)] = [
            (kVK_Space, "Space"),
            (kVK_Return, "Return"),
            (kVK_Escape, "Escape"),
            (kVK_Tab, "Tab"),
            (kVK_Delete, "Delete"),
            (kVK_ANSI_Grave, "`"),
            (kVK_ANSI_Comma, ","),
            (kVK_ANSI_Period, "."),
            (kVK_ANSI_Slash, "/"),
            (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Quote, "'"),
            (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"),
            (kVK_ANSI_Backslash, "\\"),
            (kVK_ANSI_Minus, "-"),
            (kVK_ANSI_Equal, "="),
            (kVK_ANSI_0, "0"),
            (kVK_ANSI_1, "1"),
            (kVK_ANSI_2, "2"),
            (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"),
            (kVK_ANSI_6, "6"),
            (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9"),
            (kVK_ANSI_A, "A"),
            (kVK_ANSI_B, "B"),
            (kVK_ANSI_C, "C"),
            (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"),
            (kVK_ANSI_G, "G"),
            (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"),
            (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"),
            (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"),
            (kVK_ANSI_N, "N"),
            (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"),
            (kVK_ANSI_R, "R"),
            (kVK_ANSI_S, "S"),
            (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"),
            (kVK_ANSI_V, "V"),
            (kVK_ANSI_W, "W"),
            (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z")
        ]

        for (keyCode, expected) in expectations {
            XCTAssertEqual(HotkeyConfiguration.keyName(for: UInt32(keyCode)), expected, "keyCode \(keyCode)")
        }
    }

    func testKeyNameFallsBackToNumericDescription() {
        XCTAssertEqual(HotkeyConfiguration.keyName(for: 999), "Key 999")
    }

    private func makeKeyEvent(
        type: NSEvent.EventType,
        flags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

final class UpdateChannelTests: XCTestCase {
    func testIdentifiersMatchRawValues() {
        XCTAssertEqual(UpdateChannel.stable.id, "stable")
        XCTAssertEqual(UpdateChannel.tip.id, "tip")
    }

    func testTitles() {
        XCTAssertEqual(UpdateChannel.stable.title, "Stable")
        XCTAssertEqual(UpdateChannel.tip.title, "Tip")
    }

    func testDetails() {
        XCTAssertEqual(UpdateChannel.stable.detail, "Stable releases only.")
        XCTAssertEqual(UpdateChannel.tip.detail, "Latest main-branch builds.")
    }

    func testAppcastURLs() {
        XCTAssertEqual(UpdateChannel.stable.appcastURLString, "https://suniye.kishans.in/appcast.xml")
        XCTAssertEqual(UpdateChannel.tip.appcastURLString, "https://suniye.kishans.in/appcast-tip.xml")
    }

    func testSparkleChannelNames() {
        XCTAssertNil(UpdateChannel.stable.sparkleChannelName)
        XCTAssertEqual(UpdateChannel.tip.sparkleChannelName, "tip")
    }

    func testSparkleAllowedChannels() {
        XCTAssertEqual(UpdateChannel.stable.sparkleAllowedChannels, [])
        XCTAssertEqual(UpdateChannel.tip.sparkleAllowedChannels, ["tip"])
    }
}

// MARK: - ASRModelCatalog

final class ASRModelCatalogTests: XCTestCase {
    func testModelIdentifiersMatchRawValues() {
        for modelID in ASRModelID.allCases {
            XCTAssertEqual(modelID.id, modelID.rawValue)
        }
    }

    func testCatalogHasEntryForEveryModelID() {
        for modelID in ASRModelID.allCases {
            XCTAssertEqual(ASRModelCatalog.entry(for: modelID).id, modelID)
        }
    }

    func testEstimatedSizeTextFormatsByteCount() {
        let entry = ASRModelCatalog.entry(for: .parakeetV3)

        XCTAssertEqual(
            entry.estimatedSizeText,
            "~" + ByteCountFormatter.string(fromByteCount: entry.estimatedSizeBytes, countStyle: .file)
        )
    }
}

// MARK: - AudioCaptureModels

final class AudioCaptureModelsTests: XCTestCase {
    func testInterruptionUserMessages() {
        XCTAssertEqual(AudioCaptureInterruption.deviceChanged.userMessage, "Microphone changed. Try again.")
        XCTAssertEqual(AudioCaptureInterruption.engineConfigurationChanged.userMessage, "Microphone changed. Try again.")
        XCTAssertEqual(
            AudioCaptureInterruption.deviceUnavailable.userMessage,
            "The selected microphone disconnected. Reconnect it or choose another input."
        )
        XCTAssertEqual(AudioCaptureInterruption.formatChanged.userMessage, "The microphone format changed. Try again.")
        XCTAssertEqual(AudioCaptureInterruption.serviceRestarted.userMessage, "Audio service restarted. Try again.")
        XCTAssertEqual(AudioCaptureInterruption.inputMuted.userMessage, "Your microphone is muted.")
        XCTAssertEqual(AudioCaptureInterruption.ioStoppedAbnormally.userMessage, "Audio capture was interrupted. Try again.")
        XCTAssertEqual(
            AudioCaptureInterruption.noAudioArriving.userMessage,
            "No audio is arriving from the selected microphone."
        )
        XCTAssertEqual(AudioCaptureInterruption.maximumDurationReached.userMessage, "Maximum dictation length reached.")
        XCTAssertEqual(
            AudioCaptureInterruption.systemSleep.userMessage,
            "Dictation stopped because your Mac went to sleep."
        )
    }

    func testOutcomeUserMessages() {
        XCTAssertNil(AudioCaptureOutcome.complete.userMessage)
        XCTAssertEqual(AudioCaptureOutcome.tooShort.userMessage, "Hold the shortcut a little longer and try again.")
        XCTAssertEqual(AudioCaptureOutcome.silent.userMessage, "No speech was detected from the selected microphone.")
        XCTAssertEqual(
            AudioCaptureOutcome.clipped.userMessage,
            "The microphone audio was distorted. Lower its input level and try again."
        )
        XCTAssertEqual(AudioCaptureOutcome.bufferOverflow.userMessage, "Audio capture could not keep up. Try again.")
        XCTAssertEqual(AudioCaptureOutcome.invalidSamples.userMessage, "The microphone returned invalid audio. Try again.")
        XCTAssertEqual(
            AudioCaptureOutcome.interrupted(.inputMuted).userMessage,
            AudioCaptureInterruption.inputMuted.userMessage
        )
    }
}

// MARK: - MainWindowSection

final class MainWindowSectionCoverageTests: XCTestCase {
    func testVocabularyAndLLMCompatibilityAliasesRouteToStyle() {
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye", "--open-vocabulary"]), .style)
        XCTAssertEqual(MainWindowSection.initialSelection(arguments: ["Suniye", "--open-llm"]), .style)
    }
}

// MARK: - OnboardingMagicFormatPresentation

@MainActor
final class OnboardingMagicFormatPresentationTests: XCTestCase {
    func testOptionIdentifiersMatchProviders() {
        let presenter = OnboardingMagicFormatPresenter(appState: makeTestAppState())

        XCTAssertEqual(presenter.options.map(\.id), [.localModel, .appleIntelligence])
    }

    func testReadyLocalModelOptionOffersInstalledCopy() throws {
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(localManager.preferredModelID)
        let localGemma = NoopLocalGemmaMagicFormatPostProcessor(availability: .available)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: localGemma,
            localLLMModelManager: localManager
        )
        appState.localGemmaInstallState = .installed(3_200_000_000)

        let presenter = OnboardingMagicFormatPresenter(appState: appState)
        let localOption = try XCTUnwrap(presenter.option(for: .localModel))

        XCTAssertTrue(localOption.isSelectable)
        XCTAssertNil(localOption.unavailableHelpText)
        XCTAssertEqual(localOption.description, "Runs entirely on your Mac. Already installed and ready to use.")
        XCTAssertEqual(localOption.primaryActionTitle, "Use Local Model & Continue")
    }

    func testAppleOptionHelpTextWhenAppleIntelligenceNotEnabled() throws {
        let appleOption = try appleIntelligenceOption(availability: .appleIntelligenceNotEnabled)

        XCTAssertFalse(appleOption.isSelectable)
        XCTAssertTrue(appleOption.canOpenSettings)
        XCTAssertEqual(
            appleOption.unavailableHelpText,
            "Turn on Apple Intelligence in System Settings, then come back to Suniye."
        )
    }

    func testAppleOptionHelpTextWhenModelNotReady() throws {
        let appleOption = try appleIntelligenceOption(availability: .modelNotReady)

        XCTAssertFalse(appleOption.isSelectable)
        XCTAssertFalse(appleOption.canOpenSettings)
        XCTAssertEqual(
            appleOption.unavailableHelpText,
            "Apple Intelligence is downloading or preparing its local model."
        )
    }

    func testAppleOptionHelpTextWhenDeviceNotEligible() throws {
        let appleOption = try appleIntelligenceOption(availability: .deviceNotEligible)

        XCTAssertFalse(appleOption.isSelectable)
        XCTAssertFalse(appleOption.canOpenSettings)
        XCTAssertEqual(appleOption.unavailableHelpText, "Apple Intelligence is not available on this Mac.")
    }

    func testAppleOptionHasNoHelpTextWhenAvailable() throws {
        let appleOption = try appleIntelligenceOption(availability: .available)

        XCTAssertTrue(appleOption.isSelectable)
        XCTAssertNil(appleOption.unavailableHelpText)
    }

    private func appleIntelligenceOption(
        availability: AppleFoundationModelsAvailability
    ) throws -> OnboardingMagicFormatProviderOption {
        let apple = NoopAppleMagicFormatPostProcessor(availability: availability)
        let appState = makeTestAppState(appleMagicFormatPostProcessor: apple)
        let presenter = OnboardingMagicFormatPresenter(appState: appState)
        return try XCTUnwrap(presenter.option(for: .appleIntelligence))
    }
}
