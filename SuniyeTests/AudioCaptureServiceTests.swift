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
}
