import Foundation

protocol SpeechDetecting: AnyObject {
    /// Whether 16 kHz mono `samples` hold any speech.
    func containsSpeech(_ samples: [Float]) -> Bool
}

/// Silero VAD v5 (the bundled `silero_vad_v5.onnx`, MIT) run by sherpa-onnx.
///
/// LLM-based recognizers write fluent text for silence and room noise: Qwen3-ASR
/// turns a second of quiet room into a Spanish sentence. A clip this detector
/// rejects is never decoded.
final class SpeechDetector: SpeechDetecting {
    enum DetectorError: LocalizedError, Equatable {
        case modelMissing(String)
        case creationFailed(String?)

        var errorDescription: String? {
            switch self {
            case let .modelMissing(path):
                return "Speech detector model is missing: \(path)"
            case let .creationFailed(message):
                if let message, !message.isEmpty {
                    return "Failed to create the speech detector: \(message)"
                }
                return "Failed to create the speech detector"
            }
        }
    }

    static let sampleRate = 16_000

    /// Samples handed to sherpa per call; the detector stops reading at the
    /// first speech it finds.
    private static let blockSamples = 4_096

    private let detector: OpaquePointer

    static func bundled() throws -> SpeechDetector {
        guard let path = Bundle.main.path(forResource: "silero_vad_v5", ofType: "onnx") else {
            throw DetectorError.modelMissing("silero_vad_v5.onnx")
        }
        return try SpeechDetector(modelPath: path)
    }

    init(modelPath: String) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw DetectorError.modelMissing(modelPath)
        }

        var nativeError: UnsafeMutablePointer<CChar>?
        let created = modelPath.withCString { model in
            "cpu".withCString { provider in
                var config = SherpaOnnxVadModelConfig()
                config.silero_vad.model = model
                // Silero's default. In testing it passed speech as loud as the noise
                // around it, which Qwen3-ASR still transcribes, and rejected quiet
                // rooms, white noise, tones, and speech 11 dB under the noise.
                config.silero_vad.threshold = 0.5
                // A single short word ("No.") still passes.
                config.silero_vad.min_speech_duration = 0.25
                config.silero_vad.min_silence_duration = 0.25
                config.silero_vad.max_speech_duration = 20
                config.silero_vad.window_size = 512
                config.sample_rate = Int32(Self.sampleRate)
                config.num_threads = 1
                config.provider = provider
                return SuniyeCreateVoiceActivityDetectorSafe(&config, 30, &nativeError)
            }
        }
        guard let created else {
            let message = nativeError.map { pointer in
                let value = String(cString: pointer)
                SuniyeFreeCString(pointer)
                return value
            }
            throw DetectorError.creationFailed(message)
        }
        detector = created
    }

    deinit {
        SherpaOnnxDestroyVoiceActivityDetector(detector)
    }

    func containsSpeech(_ samples: [Float]) -> Bool {
        SherpaOnnxVoiceActivityDetectorReset(detector)
        var start = 0
        while start < samples.count {
            let end = min(start + Self.blockSamples, samples.count)
            samples[start ..< end].withUnsafeBufferPointer { block in
                SherpaOnnxVoiceActivityDetectorAcceptWaveform(detector, block.baseAddress, Int32(block.count))
            }
            if hasSpeech {
                return true
            }
            start = end
        }
        SherpaOnnxVoiceActivityDetectorFlush(detector)
        return hasSpeech
    }

    /// A segment in progress, or a finished one in the queue.
    private var hasSpeech: Bool {
        SherpaOnnxVoiceActivityDetectorDetected(detector) == 1 || SherpaOnnxVoiceActivityDetectorEmpty(detector) == 0
    }
}
