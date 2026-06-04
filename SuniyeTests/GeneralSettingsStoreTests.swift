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
            soundFeedbackEnabled: true,
            hideFloatingIndicatorWhenIdle: true,
            floatingIndicatorPlacement: FloatingIndicatorPlacement(centerXRatio: 0.2, bottomYRatio: 0.15),
            hasSeenOnboardingWelcome: true,
            hasCompletedCoreOnboarding: true,
            selectedASRModelID: .senseVoice,
            updateChannel: .tip
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
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
        XCTAssertEqual(settings.updateChannel, .stable)
    }
}
