import XCTest
@testable import Suniye

/// Runs the bundled Silero VAD model, so these exercise the real detector.
final class SpeechDetectorTests: XCTestCase {
    func testSilenceNoiseAndTonesAreNotSpeech() throws {
        let detector = try SpeechDetector.bundled()
        var generator = XorShiftGenerator(seed: 0x5EED)
        let roomNoise = (0 ..< 32_000).map { _ in Float.random(in: -0.01 ... 0.01, using: &generator) }
        let loudNoise = (0 ..< 48_000).map { _ in Float.random(in: -0.1 ... 0.1, using: &generator) }
        let tone = (0 ..< 32_000).map { Float(0.2 * sin(2 * Double.pi * 440 * Double($0) / 16_000)) }

        XCTAssertFalse(detector.containsSpeech([]))
        XCTAssertFalse(detector.containsSpeech([Float](repeating: 0, count: 16_000)))
        XCTAssertFalse(detector.containsSpeech(roomNoise))
        XCTAssertFalse(detector.containsSpeech(loudNoise))
        XCTAssertFalse(detector.containsSpeech(tone))
    }

    func testSpeechIsDetectedAndTheDetectorResetsBetweenClips() async throws {
        let speech = await SpeechTestAudio.synthesizeSpeech("Please schedule the dentist appointment for Tuesday.", sampleRate: 16_000)
        try XCTSkipUnless(speech.count > 16_000, "Speech synthesis unavailable")
        let detector = try SpeechDetector.bundled()

        XCTAssertTrue(detector.containsSpeech(speech))
        XCTAssertFalse(detector.containsSpeech([Float](repeating: 0, count: 16_000)), "a speech clip must not leak into the next one")
        XCTAssertTrue(detector.containsSpeech(speech + [Float](repeating: 0, count: 16_000)))
    }

    func testShortWordAfterSilenceIsSpeech() async throws {
        let word = await SpeechTestAudio.synthesizeSpeech("No.", sampleRate: 16_000)
        try XCTSkipUnless(word.count > 4_000, "Speech synthesis unavailable")
        let detector = try SpeechDetector.bundled()

        XCTAssertTrue(detector.containsSpeech([Float](repeating: 0, count: 32_000) + word))
    }

    func testMissingModelThrows() {
        XCTAssertThrowsError(try SpeechDetector(modelPath: "/nonexistent/silero_vad_v5.onnx")) { error in
            XCTAssertEqual(error as? SpeechDetector.DetectorError, .modelMissing("/nonexistent/silero_vad_v5.onnx"))
        }
    }

    func testCorruptModelThrowsInsteadOfCrashing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-vad-\(UUID().uuidString).onnx")
        try Data(repeating: 0x5A, count: 4_096).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SpeechDetector(modelPath: url.path)) { error in
            guard case let .creationFailed(message)? = error as? SpeechDetector.DetectorError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertNotNil(message)
        }
    }

    func testErrorDescriptions() {
        XCTAssertEqual(SpeechDetector.DetectorError.modelMissing("/x.onnx").errorDescription, "Speech detector model is missing: /x.onnx")
        XCTAssertEqual(SpeechDetector.DetectorError.creationFailed("bad model").errorDescription, "Failed to create the speech detector: bad model")
        XCTAssertEqual(SpeechDetector.DetectorError.creationFailed(nil).errorDescription, "Failed to create the speech detector")
        XCTAssertEqual(SpeechDetector.DetectorError.creationFailed("").errorDescription, "Failed to create the speech detector")
    }
}

/// Deterministic noise for the detector tests.
private struct XorShiftGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
