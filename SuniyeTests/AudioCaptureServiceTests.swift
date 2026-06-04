import XCTest
@testable import Suniye

final class AudioCaptureServiceTests: XCTestCase {
    func testEchoCancellationDisabledUsesInputOnlyHALBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(echoCancellationEnabled: false),
            "inputOnlyHAL"
        )
    }

    func testEchoCancellationEnabledWithoutResolvedRoutesUsesInputOnlyHALBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(echoCancellationEnabled: true),
            "inputOnlyHAL"
        )
    }

    func testEchoCancellationEnabledWithNonBluetoothRoutesUsesVoiceProcessingBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(
                echoCancellationEnabled: true,
                inputDeviceUsesBluetooth: false,
                outputDeviceUsesBluetooth: false
            ),
            "voiceProcessingEngine"
        )
    }

    func testEchoCancellationEnabledWithBluetoothInputUsesInputOnlyHALBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(
                echoCancellationEnabled: true,
                inputDeviceUsesBluetooth: true
            ),
            "inputOnlyHAL"
        )
    }

    func testEchoCancellationDisabledWithBluetoothInputUsesInputOnlyHALBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(
                echoCancellationEnabled: false,
                inputDeviceUsesBluetooth: true
            ),
            "inputOnlyHAL"
        )
    }

    func testEchoCancellationEnabledWithBluetoothOutputUsesInputOnlyHALBackend() {
        XCTAssertEqual(
            AudioCaptureService.captureBackend(
                echoCancellationEnabled: true,
                inputDeviceUsesBluetooth: false,
                outputDeviceUsesBluetooth: true
            ),
            "inputOnlyHAL"
        )
    }

    func testRingBufferPreservesOrderAcrossWraparound() {
        guard let ring = SuniyeAudioRingBufferCreate(4) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        XCTAssertEqual(write([1, 2, 3], to: ring), 3)
        XCTAssertEqual(read(2, from: ring), [1, 2])
        XCTAssertEqual(write([4, 5, 6], to: ring), 3)
        XCTAssertEqual(read(4, from: ring), [3, 4, 5, 6])
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 0)
    }

    func testRingBufferDownmixesPlanarChannelsAndCountsDroppedFrames() {
        guard let ring = SuniyeAudioRingBufferCreate(2) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        let left: [Float] = [1, 0, -1]
        let right: [Float] = [-1, 1, 1]
        let written = left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                let channels: [UnsafePointer<Float>?] = [leftBuffer.baseAddress, rightBuffer.baseAddress]
                return channels.withUnsafeBufferPointer {
                    SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 2, 3)
                }
            }
        }

        XCTAssertEqual(written, 2)
        XCTAssertEqual(read(2, from: ring), [0, 0.5])
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 1)
    }

    func testCapturedAudioHealthRejectsUnsafeAudio() {
        XCTAssertEqual(
            CapturedAudio(samples: [0.2], sampleRate: 16_000).outcome,
            .tooShort
        )
        XCTAssertEqual(
            CapturedAudio(samples: Array(repeating: 0, count: 1_600), sampleRate: 16_000).outcome,
            .silent
        )
        XCTAssertEqual(
            CapturedAudio(samples: Array(repeating: 1, count: 1_600), sampleRate: 16_000).outcome,
            .clipped
        )
        XCTAssertEqual(
            CapturedAudio(
                samples: Array(repeating: 0.2, count: 1_600),
                sampleRate: 16_000,
                droppedSampleCount: 1
            ).outcome,
            .bufferOverflow
        )
        var invalid = Array(repeating: Float(0.2), count: 1_600)
        invalid[42] = .nan
        XCTAssertEqual(CapturedAudio(samples: invalid, sampleRate: 16_000).outcome, .invalidSamples)
    }

    func testCapturedAudioHealthAcceptsUsableAudio() {
        let captured = CapturedAudio(
            samples: Array(repeating: 0.2, count: 1_600),
            sampleRate: 16_000
        )

        XCTAssertEqual(captured.outcome, .complete)
        XCTAssertEqual(captured.health.durationSeconds, 0.1, accuracy: 0.000_1)
        XCTAssertEqual(captured.health.rms, 0.2, accuracy: 0.000_1)
    }

    func testRoutePrivacyLogDoesNotContainDeviceIdentity() {
        let route = AudioRouteSnapshot(
            preferredInputDeviceID: "private-device-uid",
            effectiveInputDeviceID: "private-device-uid",
            effectiveInputName: "Kishan's Private Microphone",
            inputTransport: .bluetooth,
            outputTransport: .bluetooth,
            inputSampleRate: 48_000,
            inputChannelCount: 1,
            requestedEchoCancellation: true,
            effectiveEchoCancellation: false,
            backend: .inputOnlyHAL,
            fallbackReason: "bluetooth_route"
        )

        XCTAssertFalse(route.privacySafeLogValue.contains("private-device-uid"))
        XCTAssertFalse(route.privacySafeLogValue.contains("Kishan"))
        XCTAssertTrue(route.privacySafeLogValue.contains("input=bluetooth"))
    }

    private func write(_ samples: [Float], to ring: OpaquePointer) -> Int {
        samples.withUnsafeBufferPointer {
            SuniyeAudioRingBufferWrite(ring, $0.baseAddress, samples.count)
        }
    }

    private func read(_ count: Int, from ring: OpaquePointer) -> [Float] {
        var result = Array(repeating: Float(0), count: count)
        let readCount = result.withUnsafeMutableBufferPointer {
            SuniyeAudioRingBufferRead(ring, $0.baseAddress, count)
        }
        return Array(result.prefix(readCount))
    }
}
