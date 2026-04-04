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
