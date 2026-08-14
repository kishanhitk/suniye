import XCTest
@testable import Suniye

/// Throwaway diagnostic: streams the offline-validated positive wav through
/// the app's Swift detector in drain-sized chunks. Not for CI (depends on
/// /tmp fixtures); delete after the wake-path investigation.
final class WakeWordStreamingDiagnosticTests: XCTestCase {
    func testStreamingDetectsSynthesizedPositive() throws {
        let path = ProcessInfo.processInfo.environment["WAKE_FIXTURE"] ?? "/tmp/kws_pos1.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("diagnostic fixture missing")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // Walk RIFF chunks to the data payload (say(1) emits a JUNK chunk).
        var offset = 12
        var payload = Data()
        while offset + 8 <= data.count {
            let chunkID = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = data[offset + 4..<offset + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            if chunkID == "data" {
                payload = data.subdata(in: (offset + 8)..<min(offset + 8 + Int(size), data.count))
                break
            }
            offset += 8 + Int(size) + (Int(size) % 2)
        }
        let samples = payload.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float($0) / 32_768 }
        }
        XCTAssertGreaterThan(samples.count, 16_000 / 2)

        let detector = try SherpaWakeWordDetector()
        var detected = false
        var index = 0
        while index < samples.count {
            let chunk = Array(samples[index..<min(index + 320, samples.count)])
            if detector.accept(samples: chunk, sampleRate: 16_000) {
                detected = true
            }
            index += 320
        }
        // Trailing silence so the final frames decode.
        for _ in 0..<50 {
            if detector.accept(samples: [Float](repeating: 0, count: 320), sampleRate: 16_000) {
                detected = true
            }
        }
        XCTAssertTrue(detected, "Swift streaming path missed the offline-validated positive")
    }

}
