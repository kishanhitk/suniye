import XCTest
@testable import Suniye

final class AudioCaptureServiceTests: XCTestCase {
    func testEchoCancellationDisabledUsesHALInputBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(echoCancellationEnabled: false),
            "halInput"
        )
    }

    func testEchoCancellationEnabledUsesVoiceProcessingBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(echoCancellationEnabled: true),
            "voiceProcessingEngine"
        )
    }
}
