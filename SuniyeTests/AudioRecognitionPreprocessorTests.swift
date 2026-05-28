import XCTest
@testable import Suniye

final class AudioRecognitionPreprocessorTests: XCTestCase {
    func testQuietSpeechLikeAudioIsAmplifiedForRecognition() {
        let samples = sineWave(amplitude: 0.013, seconds: 1)
        let inputStats = AudioRecognitionPreprocessor.stats(of: samples)

        let prepared = AudioRecognitionPreprocessor.prepareForRecognition(samples)

        XCTAssertGreaterThan(prepared.gain, 1)
        XCTAssertGreaterThan(prepared.outputStats.rms, inputStats.rms * 2)
        XCTAssertLessThanOrEqual(prepared.outputStats.peak, 0.85 + 0.0001)
        XCTAssertTrue(prepared.samples.allSatisfy { abs($0) <= 1 })
    }

    func testNearSilenceIsNotAmplified() {
        let samples = sineWave(amplitude: 0.001, seconds: 1)

        let prepared = AudioRecognitionPreprocessor.prepareForRecognition(samples)

        XCTAssertFalse(prepared.didNormalize)
        XCTAssertEqual(prepared.gain, 1)
        XCTAssertEqual(prepared.samples, samples)
    }

    func testAudioBelowMinimumGainThresholdIsNotMarkedAsNormalized() {
        let samples = sineWave(amplitude: 0.045, seconds: 1)

        let prepared = AudioRecognitionPreprocessor.prepareForRecognition(samples)

        XCTAssertFalse(prepared.didNormalize)
        XCTAssertEqual(prepared.gain, 1)
        XCTAssertEqual(prepared.samples, samples)
    }

    func testNormalLevelAudioIsLeftUnchanged() {
        let samples = sineWave(amplitude: 0.08, seconds: 1)

        let prepared = AudioRecognitionPreprocessor.prepareForRecognition(samples)

        XCTAssertFalse(prepared.didNormalize)
        XCTAssertEqual(prepared.gain, 1)
        XCTAssertEqual(prepared.samples, samples)
    }

    private func sineWave(amplitude: Float, seconds: Double, sampleRate: Int = 16_000) -> [Float] {
        let count = Int(Double(sampleRate) * seconds)
        return (0 ..< count).map { index in
            let phase = 2 * Double.pi * 220 * Double(index) / Double(sampleRate)
            return Float(sin(phase)) * amplitude
        }
    }
}
