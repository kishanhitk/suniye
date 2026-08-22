import Carbon
import XCTest
@testable import Suniye

final class GeneralSettingsStoreTests: XCTestCase {
    func testStoreRoundTrip() {
        let suite = "dev.suniye.tests.general.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")

        let settings = GeneralSettings(
            preferredInputDeviceID: "usb-mic",
            preferredInputDeviceName: "USB Microphone",
            autoSubmitEnabled: true,
            hotkeyConfiguration: .keyCombo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey)),
            pasteLastTranscriptHotkeyConfiguration: .keyCombo(
                keyCode: UInt32(kVK_ANSI_P),
                carbonModifiers: UInt32(controlKey | cmdKey)
            ),
            soundFeedbackEnabled: true,
            hideFloatingIndicatorWhenIdle: true,
            floatingIndicatorPlacement: FloatingIndicatorPlacement(centerXRatio: 0.2, bottomYRatio: 0.15),
            hasSeenOnboardingWelcome: true,
            hasCompletedCoreOnboarding: true,
            selectedASRModelID: .senseVoice,
            updateChannel: .tip,
            shareAnalyticsEnabled: false
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
        XCTAssertEqual(store.load().shareAnalyticsEnabled, false)
    }

    func testUnknownASRModelIDFallsBackWithoutResettingOtherSettings() {
        let suite = "dev.suniye.tests.general.unknown-model.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")
        let payload = """
        {
          "preferredInputDeviceID": "usb-mic",
          "autoSubmitEnabled": true,
          "echoCancellationEnabled": true,
          "hasSeenOnboardingWelcome": true,
          "hasCompletedCoreOnboarding": true,
          "selectedASRModelID": "futureModel",
          "updateChannel": "futureChannel"
        }
        """

        defaults.set(Data(payload.utf8), forKey: "general")
        let loaded = store.load()

        XCTAssertEqual(loaded.preferredInputDeviceID, "usb-mic")
        XCTAssertEqual(loaded.autoSubmitEnabled, true)
        XCTAssertEqual(loaded.echoCancellationEnabled, true)
        XCTAssertEqual(loaded.soundFeedbackEnabled, false)
        XCTAssertEqual(loaded.hasSeenOnboardingWelcome, true)
        XCTAssertEqual(loaded.hasCompletedCoreOnboarding, true)
        XCTAssertEqual(loaded.selectedASRModelID, .parakeetV3)
        XCTAssertEqual(loaded.updateChannel, .stable)
    }

    func testLiveTranscriptionPreviewFlagRoundTripsAndDefaultsFalseForLegacyBlob() {
        let suite = "dev.suniye.tests.general.livePreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")

        store.save(GeneralSettings(liveTranscriptionPreviewEnabled: true))
        XCTAssertTrue(store.load().liveTranscriptionPreviewEnabled)

        // Blob saved before the key existed must decode the flag as the default (false).
        defaults.set(Data(#"{"autoSubmitEnabled": true}"#.utf8), forKey: "general")
        XCTAssertFalse(store.load().liveTranscriptionPreviewEnabled)
    }

    func testAccessibilityDragHelperFlagRoundTrips() {
        let suite = "dev.suniye.tests.general.dragHelper.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")

        let settings = GeneralSettings(accessibilityDragHelperEnabled: false)
        store.save(settings)

        XCTAssertFalse(store.load().accessibilityDragHelperEnabled)
    }

    func testAccessibilityDragHelperDefaultsTrueForLegacyBlob() {
        let suite = "dev.suniye.tests.general.dragHelper.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")
        // Blob saved before the key existed must decode the flag as the default (true).
        let legacyJSON = """
        {
          "preferredInputDeviceID": "usb-mic",
          "autoSubmitEnabled": true
        }
        """
        defaults.set(Data(legacyJSON.utf8), forKey: "general")

        XCTAssertTrue(store.load().accessibilityDragHelperEnabled)
    }

    func testOnboardingProgressAndNewFlagsRoundTrip() {
        let suite = "dev.suniye.tests.general.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")

        let settings = GeneralSettings(
            onboardingProgress: .speakReached,
            firstLaunchRecorded: true,
            lastKnownAccessibilityGranted: true,
            magicFormatNudgeDismissed: true,
            localGemmaDownloadCancelled: true
        )
        store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded.onboardingProgress, .speakReached)
        XCTAssertTrue(loaded.firstLaunchRecorded)
        XCTAssertTrue(loaded.lastKnownAccessibilityGranted)
        XCTAssertTrue(loaded.magicFormatNudgeDismissed)
        XCTAssertTrue(loaded.localGemmaDownloadCancelled)
    }

    func testLegacyBlobDecodesNilProgressAndFalseFlags() {
        let suite = "dev.suniye.tests.general.onboarding.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")
        defaults.set(Data(#"{"hasSeenOnboardingWelcome": true, "hasCompletedCoreOnboarding": false}"#.utf8), forKey: "general")

        let loaded = store.load()

        XCTAssertNil(loaded.onboardingProgress, "older blobs must trigger the Bool migration path")
        XCTAssertFalse(loaded.firstLaunchRecorded)
        XCTAssertFalse(loaded.lastKnownAccessibilityGranted)
        XCTAssertFalse(loaded.magicFormatNudgeDismissed)
    }

    func testUnknownOnboardingProgressValueDegradesToNil() {
        let suite = "dev.suniye.tests.general.onboarding.future.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")
        defaults.set(Data(#"{"onboardingProgress": "futureState", "autoSubmitEnabled": true}"#.utf8), forKey: "general")

        let loaded = store.load()

        XCTAssertNil(loaded.onboardingProgress, "a future enum case must not fail the whole settings blob")
        XCTAssertTrue(loaded.autoSubmitEnabled)
    }

    func testHotkeyDisplayStringsMatchUIExamples() {
        XCTAssertEqual(HotkeyConfiguration.globe.displayString, "Globe")
        XCTAssertEqual(
            HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey)).displayString,
            "Option + Space"
        )
        XCTAssertEqual(
            HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: 0).displayString,
            "`"
        )
        XCTAssertEqual(HotkeyConfiguration.pasteLastTranscriptDefault.compactDisplayString, "⌃⌘V")
        XCTAssertTrue(HotkeyConfiguration.pasteLastTranscriptDefault.isModifiedKeyCombo)
        XCTAssertFalse(HotkeyConfiguration.globe.isModifiedKeyCombo)
        XCTAssertFalse(
            HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: 0).isModifiedKeyCombo
        )
    }

    func testStoreLoadBackfillsNewIndicatorFields() throws {
        let suite = "dev.suniye.tests.general.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")

        let legacyJSON = """
        {
          "preferredInputDeviceID": "usb-mic",
          "autoSubmitEnabled": true,
          "hotkeyConfiguration": {
            "kind": "globe",
            "keyCode": 63,
            "carbonModifiers": 0
          },
          "echoCancellationEnabled": false,
          "hasSeenOnboardingWelcome": true,
          "hasCompletedCoreOnboarding": false
        }
        """
        defaults.set(try XCTUnwrap(legacyJSON.data(using: .utf8)), forKey: "general")

        let settings = store.load()

        XCTAssertFalse(settings.hideFloatingIndicatorWhenIdle)
        XCTAssertNil(settings.floatingIndicatorPlacement)
        XCTAssertFalse(settings.soundFeedbackEnabled)
        XCTAssertNil(settings.preferredInputDeviceName)
        XCTAssertEqual(settings.pasteLastTranscriptHotkeyConfiguration, .pasteLastTranscriptDefault)
        XCTAssertEqual(settings.updateChannel, .stable)
    }
}
