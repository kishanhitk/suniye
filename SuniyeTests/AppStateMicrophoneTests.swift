import XCTest
@testable import Suniye

@MainActor
final class AppStateMicrophoneTests: XCTestCase {
    func testDeviceListRefreshUpdatesPersistedDeviceName() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(id: "usb-1", name: "New Name", isDefault: false, transport: .usb),
        ]
        let settingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: "usb-1",
                preferredInputDeviceName: "Old Name"
            )
        )

        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            generalSettingsStore: settingsStore
        )
        appState.microphone.refreshInputDevices()

        XCTAssertEqual(appState.microphone.preferredInputDeviceName, "New Name")
        XCTAssertEqual(settingsStore.latest.preferredInputDeviceName, "New Name")
    }

    func testSelectedInputDeviceNameFallbacks() {
        // A route names the microphone in use, whatever the selection.
        let routed = makeTestAppState()
        routed.microphone.selectedInputDeviceID = "ghost-device"
        XCTAssertEqual(routed.microphone.activeInputDeviceName, "System Microphone")

        // No route: fall back to the default device, then to "System Default".
        let unrouted = StubAudioCaptureService()
        unrouted.routeSnapshotError = AudioCaptureServiceError.noInputDevice
        unrouted.availableDevices = [
            AudioInputDevice(id: "mac-mic", name: "Mac Microphone", isDefault: true, transport: .builtIn),
        ]
        let fallbackState = makeTestAppState(audioCaptureService: unrouted)
        XCTAssertEqual(fallbackState.microphone.activeInputDeviceName, "Mac Microphone")

        fallbackState.microphone.availableInputDevices = []
        XCTAssertEqual(fallbackState.microphone.activeInputDeviceName, "System Default")
        XCTAssertEqual(fallbackState.microphone.effectiveInputDeviceStatusText, "No microphone is available.")

        // Selection points at a vanished device with no remembered name.
        fallbackState.microphone.selectedInputDeviceID = "ghost-device"
        XCTAssertEqual(fallbackState.microphone.activeInputDeviceName, "Selected Microphone")
    }

    func testAudioRouteWarningTextEchoCancellationMismatch() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.route = AudioRouteSnapshot(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: "mac-mic",
            effectiveInputName: "Mac Microphone",
            inputTransport: .builtIn,
            outputTransport: .builtIn,
            inputSampleRate: 16_000,
            inputChannelCount: 1,
            requestedEchoCancellation: true,
            effectiveEchoCancellation: false,
            backend: .inputOnlyHAL,
            fallbackReason: nil,
            standIn: nil
        )
        let appState = makeTestAppState(audioCaptureService: audioCapture)

        XCTAssertEqual(
            appState.microphone.audioRouteWarningText,
            "Echo cancellation is unavailable for the current audio route."
        )
    }

    func testRecommendedInputDeviceOrderingPrefersDefaultThenBuiltInThenName() {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(id: "usb-z", name: "Zeta USB", isDefault: false, transport: .usb),
            AudioInputDevice(id: "built-b", name: "Beta Built-in", isDefault: false, transport: .builtIn),
            AudioInputDevice(id: "built-a", name: "Alpha Built-in", isDefault: false, transport: .builtIn),
        ]
        audioCapture.route = AudioRouteSnapshot(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: "bt-current",
            effectiveInputName: "BT Headset",
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
        let appState = makeTestAppState(audioCaptureService: audioCapture)

        // Built-in beats USB; ties break alphabetically.
        XCTAssertEqual(appState.microphone.recommendedInputDevice?.id, "built-a")

        audioCapture.availableDevices.append(
            AudioInputDevice(id: "usb-default", name: "Default USB", isDefault: true, transport: .usb)
        )
        appState.microphone.refreshInputDevices()

        // A default device wins over everything else.
        XCTAssertEqual(appState.microphone.recommendedInputDevice?.id, "usb-default")
    }
}
