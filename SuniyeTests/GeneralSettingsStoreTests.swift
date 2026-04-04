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
            autoSubmitEnabled: true,
            hotkeyConfiguration: .keyCombo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey)),
            hasSeenOnboardingWelcome: true,
            hasCompletedCoreOnboarding: true,
            selectedASRModelID: .senseVoice
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
          "selectedASRModelID": "futureModel"
        }
        """

        defaults.set(Data(payload.utf8), forKey: "general")
        let loaded = store.load()

        XCTAssertEqual(loaded.preferredInputDeviceID, "usb-mic")
        XCTAssertEqual(loaded.autoSubmitEnabled, true)
        XCTAssertEqual(loaded.echoCancellationEnabled, true)
        XCTAssertEqual(loaded.hasSeenOnboardingWelcome, true)
        XCTAssertEqual(loaded.hasCompletedCoreOnboarding, true)
        XCTAssertEqual(loaded.selectedASRModelID, .parakeetV3)
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
}
