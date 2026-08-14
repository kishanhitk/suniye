import XCTest
@testable import Suniye

/// Streams a known wake-phrase recording through the real detector in
/// drain-sized chunks — the app's exact acoustic path. Guards the keyword
/// loading regressions found live: sherpa ignores in-memory keyword buffers,
/// and a non-null empty buffer disables the keywords file too. If keyword
/// loading breaks again, this fails; the silence/tone negatives alone would
/// keep passing.
final class WakeWordStreamingTests: XCTestCase {
    func testStreamingDetectsWakePhraseFixture() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "wake-positive-hey-suniye",
                withExtension: "wav"
            )
        )
        let samples = try Self.pcm16MonoSamples(from: url)
        XCTAssertGreaterThan(samples.count, 8_000)

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
        // Trailing silence lets the final frames decode (chunked model).
        for _ in 0..<50 where !detected {
            if detector.accept(samples: [Float](repeating: 0, count: 320), sampleRate: 16_000) {
                detected = true
            }
        }
        XCTAssertTrue(detected, "wake keywords failed to load or match")
    }

    /// RIFF-chunk-aware PCM16 reader; `say(1)` fixtures carry a JUNK chunk,
    /// so a fixed 44-byte header offset would misread them.
    private static func pcm16MonoSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = data[offset + 4..<offset + 8].withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self)
            }
            if chunkID == "data" {
                let payload = data.subdata(in: (offset + 8)..<min(offset + 8 + Int(size), data.count))
                return payload.withUnsafeBytes { raw in
                    raw.bindMemory(to: Int16.self).map { Float($0) / 32_768 }
                }
            }
            offset += 8 + Int(size) + (Int(size) % 2)
        }
        return []
    }
}
