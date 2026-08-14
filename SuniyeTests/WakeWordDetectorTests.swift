import XCTest
@testable import Suniye

/// The bundled models plus real sherpa inference, headless: creation must
/// succeed from the app bundle, silence and tones must not wake, and the
/// energy fallback must classify frames sanely. Positive wake detection needs
/// real speech audio and is covered by the live e2e script, not unit tests.
final class WakeWordDetectorTests: XCTestCase {
    func testBundledModelsArePresent() throws {
        for file in [
            "kws-encoder.int8.onnx", "kws-decoder.int8.onnx",
            "kws-joiner.int8.onnx", "kws-tokens.txt", "silero_vad.onnx",
        ] {
            XCTAssertNoThrow(try WakeWordModelLocator.url(for: file), file)
        }
    }

    func testMissingModelThrows() {
        XCTAssertThrowsError(try WakeWordModelLocator.url(for: "no-such-model.onnx"))
    }

    func testDetectorCreatesAndIgnoresSilenceAndTone() throws {
        let detector = try SherpaWakeWordDetector()

        let silence = [Float](repeating: 0, count: 16_000)
        XCTAssertFalse(detector.accept(samples: silence, sampleRate: 16_000))

        // A 440 Hz tone is voiced-adjacent input, not the wake phrase.
        let tone = (0..<16_000).map { Float(sin(2 * .pi * 440 * Double($0) / 16_000)) * 0.3 }
        XCTAssertFalse(detector.accept(samples: tone, sampleRate: 16_000))

        detector.reset()
    }

    func testSileroDetectorCreatesAndRejectsSilence() throws {
        let detector = try SileroSpeechActivityDetector()
        let silence = [Float](repeating: 0, count: 1_600)
        XCTAssertFalse(detector.isSpeech(samples16k: silence))
        detector.reset()
    }

    func testEnergyDetectorThresholds() {
        let detector = EnergySpeechActivityDetector(threshold: 0.015)
        XCTAssertFalse(detector.isSpeech(samples16k: []))
        XCTAssertFalse(detector.isSpeech(samples16k: [Float](repeating: 0.001, count: 320)))
        XCTAssertTrue(detector.isSpeech(samples16k: [Float](repeating: 0.1, count: 320)))
    }
}

final class AudioResamplerTests: XCTestCase {
    func testIdentityWhenRatesMatch() {
        let input: [Float] = [0.1, 0.2, 0.3]
        XCTAssertEqual(AudioResampler.resample(input, from: 16_000, to: 16_000), input)
    }

    func testDownsamplesByHalf() {
        let input = (0..<1_000).map { Float($0) }
        let output = AudioResampler.resample(input, from: 32_000, to: 16_000)
        XCTAssertEqual(output.count, 500)
        XCTAssertEqual(output[10], 20, accuracy: 0.001)
    }

    func testUpsamplingInterpolatesBetweenNeighbors() {
        let output = AudioResampler.resample([0, 1], from: 8_000, to: 16_000)
        XCTAssertEqual(output.count, 4)
        XCTAssertEqual(output[1], 0.5, accuracy: 0.001)
    }

    func testDegenerateInputsReturnEmpty() {
        XCTAssertTrue(AudioResampler.resample([], from: 48_000, to: 16_000).isEmpty)
        XCTAssertTrue(AudioResampler.resample([0.5], from: 0, to: 16_000).isEmpty)
    }
}
