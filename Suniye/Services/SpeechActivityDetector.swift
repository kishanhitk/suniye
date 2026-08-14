import Foundation

/// Per-frame "is this speech" judgment for the turn endpointer.
protocol SpeechActivityDetecting: AnyObject {
    /// Samples must be 16 kHz mono.
    func isSpeech(samples16k: [Float]) -> Bool
    func reset()
}

/// Silero VAD via the bundled sherpa dylib. Primary signal for the endpointer;
/// the energy fallback lives in the controller.
final class SileroSpeechActivityDetector: SpeechActivityDetecting {
    private let vad: SherpaOnnxVoiceActivityDetectorWrapper

    init(bundle: Bundle = .main) throws {
        let model = try WakeWordModelLocator.url(for: "silero_vad.onnx", in: bundle)
        var config = sherpaOnnxVadModelConfig(
            sileroVad: sherpaOnnxSileroVadModelConfig(model: model.path),
            sampleRate: 16000,
            numThreads: 1
        )
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &config, buffer_size_in_seconds: 10)
    }

    func isSpeech(samples16k: [Float]) -> Bool {
        vad.acceptWaveform(samples: samples16k)
        return vad.isSpeechDetected()
    }

    func reset() {
        vad.reset()
    }
}

/// RMS-energy fallback when the VAD model cannot load. Coarse but functional.
final class EnergySpeechActivityDetector: SpeechActivityDetecting {
    private let threshold: Float

    init(threshold: Float = 0.015) {
        self.threshold = threshold
    }

    func isSpeech(samples16k: [Float]) -> Bool {
        guard !samples16k.isEmpty else {
            return false
        }
        let sumOfSquares = samples16k.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = (sumOfSquares / Float(samples16k.count)).squareRoot()
        return rms >= threshold
    }

    func reset() {}
}
