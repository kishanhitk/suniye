import Foundation

/// Detects the wake phrase in a continuous sample stream.
protocol WakeWordDetecting: AnyObject {
    /// Feeds samples; returns true when the wake phrase was detected.
    /// The internal stream resets after a detection.
    func accept(samples: [Float], sampleRate: Double) -> Bool
    /// Drops any partial acoustic state (tap pause, suppression window).
    func reset()
}

enum WakeWordDetectorError: Error, Equatable {
    case modelMissing(String)
    case spotterCreationFailed
}

/// Locates the bundled wake-word and VAD models (`Suniye/WakeWord`, copied as
/// a folder reference).
enum WakeWordModelLocator {
    static func modelDirectory(in bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent("WakeWord", isDirectory: true)
    }

    static func url(for file: String, in bundle: Bundle = .main) throws -> URL {
        guard let directory = modelDirectory(in: bundle) else {
            throw WakeWordDetectorError.modelMissing(file)
        }
        let url = directory.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WakeWordDetectorError.modelMissing(file)
        }
        return url
    }
}

/// Sherpa keyword spotter wrapped for the "Hey Suniye" phrase.
///
/// The keyword lines are precomputed BPE token sequences for the bundled
/// gigaspeech KWS model (validated against synthesized positives and
/// near-miss negatives; see the implementation plan). The truncated
/// `▁HE Y ▁SU N I` variant carries recall; the others add coverage.
final class SherpaWakeWordDetector: WakeWordDetecting {
    static let keywords = """
    ▁HE Y ▁SU N I Y E :3.0 #0.05
    ▁HE Y ▁SO ON I Y E :3.0 #0.05
    ▁HE Y ▁SU N I Y A Y :3.0 #0.05
    ▁HE Y ▁SO ON I Y A Y :3.0 #0.05
    ▁HE Y ▁SU NE E Y E :3.0 #0.05
    ▁HE Y ▁SU N I :3.0 #0.05
    """

    private let spotter: SherpaOnnxKeywordSpotterWrapper

    init(bundle: Bundle = .main) throws {
        let encoder = try WakeWordModelLocator.url(for: "kws-encoder.int8.onnx", in: bundle)
        let decoder = try WakeWordModelLocator.url(for: "kws-decoder.int8.onnx", in: bundle)
        let joiner = try WakeWordModelLocator.url(for: "kws-joiner.int8.onnx", in: bundle)
        let tokens = try WakeWordModelLocator.url(for: "kws-tokens.txt", in: bundle)

        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokens.path,
            transducer: sherpaOnnxOnlineTransducerModelConfig(
                encoder: encoder.path,
                decoder: decoder.path,
                joiner: joiner.path
            ),
            numThreads: 1,
            provider: "cpu"
        )
        var config = sherpaOnnxKeywordSpotterConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80),
            modelConfig: modelConfig,
            keywordsFile: "",
            maxActivePaths: 4,
            numTrailingBlanks: 1,
            keywordsScore: 2.0,
            keywordsThreshold: 0.25,
            keywordsBuf: Self.keywords,
            keywordsBufSize: Self.keywords.utf8.count
        )
        spotter = SherpaOnnxKeywordSpotterWrapper(config: &config)
        guard spotter.spotter != nil, spotter.stream != nil else {
            throw WakeWordDetectorError.spotterCreationFailed
        }
    }

    func accept(samples: [Float], sampleRate: Double) -> Bool {
        spotter.acceptWaveform(samples: samples, sampleRate: Int(sampleRate))
        var detected = false
        while spotter.isReady() {
            spotter.decode()
            let result = spotter.getResult()
            if !result.keyword.isEmpty {
                detected = true
                spotter.reset()
            }
        }
        return detected
    }

    func reset() {
        spotter.reset()
    }
}
