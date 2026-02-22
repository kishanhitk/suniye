import XCTest
import CoreAudio
@testable import VibeStoke

@MainActor
final class AppStateGeneralSettingsTests: XCTestCase {
    func testLaunchAtLoginErrorIsSurfaced() {
        let appState = AppState(
            appPreferencesStore: TestPreferencesStore(),
            audioDeviceService: TestAudioDeviceService(),
            launchAtLoginService: ThrowingLaunchAtLoginService(),
            startServices: false,
            llmE2EMode: .none
        )

        appState.setLaunchAtLoginEnabled(true)

        XCTAssertFalse(appState.launchAtLoginEnabled)
        XCTAssertNotNil(appState.launchAtLoginError)
    }

    func testInputDeviceFallbackToDefaultWhenMissing() {
        let preferencesStore = TestPreferencesStore(
            initial: AppPreferences(
                hotkeyShortcut: .defaultHoldToTalk,
                selectedInputDeviceUID: "missing-mic",
                launchAtLoginEnabled: false
            )
        )

        let appState = AppState(
            appPreferencesStore: preferencesStore,
            audioDeviceService: TestAudioDeviceService(),
            launchAtLoginService: StableLaunchAtLoginService(),
            startServices: false,
            llmE2EMode: .none
        )

        XCTAssertEqual(appState.selectedInputDeviceUID, "default-mic")

        appState.selectInputDevice(uid: "missing-mic")

        XCTAssertEqual(appState.selectedInputDeviceUID, "default-mic")
        XCTAssertEqual(appState.inputDeviceStatusMessage, "Selected input device is unavailable.")
    }
}

private final class TestPreferencesStore: AppPreferencesStoreProtocol {
    private var value: AppPreferences

    init(initial: AppPreferences = AppPreferences()) {
        value = initial
    }

    func load() -> AppPreferences {
        value
    }

    func save(_ preferences: AppPreferences) {
        value = preferences
    }
}

private final class TestAudioDeviceService: AudioDeviceServiceProtocol {
    func availableInputDevices() -> [AudioInputDevice] {
        [AudioInputDevice(uid: "default-mic", name: "Default Mic", isDefault: true)]
    }

    func defaultInputDeviceUID() -> String? {
        "default-mic"
    }

    func resolveSelectedInputDeviceUID(_ preferredUID: String?) -> String? {
        if preferredUID == nil || preferredUID == "default-mic" {
            return "default-mic"
        }
        return "default-mic"
    }

    func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        nil
    }
}

private final class ThrowingLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    func isEnabled() -> Bool {
        false
    }

    func setEnabled(_ enabled: Bool) throws {
        throw LaunchAtLoginError.operationFailed("simulated failure")
    }
}

private final class StableLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    private var enabled = false

    func isEnabled() -> Bool {
        enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
    }
}
