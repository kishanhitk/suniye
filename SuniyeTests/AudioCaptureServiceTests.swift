import XCTest
@testable import Suniye

final class AudioCaptureServiceTests: XCTestCase {
    func testEchoCancellationDisabledUsesStandardEngineBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(echoCancellationEnabled: false),
            "standardEngine"
        )
    }

    func testEchoCancellationEnabledUsesVoiceProcessingBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(echoCancellationEnabled: true),
            "voiceProcessingEngine"
        )
    }

    func testEchoCancellationEnabledWithNonBluetoothInputUsesVoiceProcessingBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(
                echoCancellationEnabled: true,
                inputDeviceUsesBluetooth: false
            ),
            "voiceProcessingEngine"
        )
    }

    func testEchoCancellationEnabledWithBluetoothInputUsesStandardEngineBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(
                echoCancellationEnabled: true,
                inputDeviceUsesBluetooth: true
            ),
            "standardEngine"
        )
    }

    func testEchoCancellationDisabledWithBluetoothInputUsesStandardEngineBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(
                echoCancellationEnabled: false,
                inputDeviceUsesBluetooth: true
            ),
            "standardEngine"
        )
    }
}
