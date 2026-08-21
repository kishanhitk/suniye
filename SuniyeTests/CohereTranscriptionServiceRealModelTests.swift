import XCTest
@testable import Suniye

/// Opt-in end-to-end check of the Cohere engine against the real 2.9 GB model:
/// loads both ONNX sessions, decodes a short utterance, and decodes a > 35 s
/// clip so the chunk-and-join path runs. Skipped unless enabled, so CI (which
/// has no model) and routine local runs stay fast.
///
/// Run it:
///   TEST_RUNNER_SUNIYE_RUN_COHERE_TESTS=1 \
///   [TEST_RUNNER_SUNIYE_COHERE_MODEL_DIR=/path/to/model] \
///   xcodebuild test -project Suniye.xcodeproj -scheme Suniye \
///     -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData \
///     -only-testing:SuniyeTests/CohereTranscriptionServiceRealModelTests \
///     ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
final class CohereTranscriptionServiceRealModelTests: XCTestCase {
    private static let shortText = "Please schedule the dentist appointment for Tuesday at three thirty, and remind me to buy milk on the way home."

    private static let longText = """
    The quick brown fox jumps over the lazy dog. Speech recognition has come a long way, and running it \
    entirely on device keeps your dictation private and fast. This sentence exists only to give the \
    transcriber a realistic amount of audio to process. We need well over thirty five seconds of speech \
    here so that the chunking path is exercised, which means the audio is split at the quietest point \
    inside the last five seconds before the boundary. After that split, each chunk is encoded and decoded \
    separately, and the resulting texts are joined with a single space. The model itself never sees more \
    than thirty five seconds at a time, which keeps its attention window within the range it was trained \
    on. Longer recordings simply produce more chunks, each decoded on its own before the texts are joined. \
    Finally, this closing sentence pushes the recording comfortably past the limit so that two chunks are \
    produced rather than one.
    """

    private static func loadService() async throws -> CohereTranscriptionService {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SUNIYE_RUN_COHERE_TESTS"] == "1",
            "Set SUNIYE_RUN_COHERE_TESTS=1 to run the Cohere real-model tests"
        )

        let config: RecognizerConfig
        if let directory = ProcessInfo.processInfo.environment["SUNIYE_COHERE_MODEL_DIR"] {
            let manifest = ASRModelCatalog.entry(for: .cohereTranscribe).manifest
            config = RecognizerConfig(
                modelID: .cohereTranscribe,
                family: .cohereTranscribe,
                tokensPath: "\(directory)/\(manifest.tokens)",
                numThreads: 4,
                encoderPath: "\(directory)/\(manifest.encoder!)",
                decoderPath: "\(directory)/\(manifest.decoder!)",
                language: "en"
            )
        } else {
            let manager = ModelManager()
            try XCTSkipUnless(manager.isInstalled(.cohereTranscribe), "Cohere Transcribe is not installed")
            config = try manager.makeRecognizerConfig(for: .cohereTranscribe)
        }

        let service = CohereTranscriptionService()
        try await service.loadModel(config: config)
        return service
    }

    func testTranscribesShortUtterance() async throws {
        let service = try await Self.loadService()
        let samples = await SpeechTestAudio.synthesizeSpeech(Self.shortText, sampleRate: 16_000)
        try XCTSkipUnless(samples.count > 16_000, "Speech synthesis unavailable")

        let started = DispatchTime.now()
        let text = try await service.transcribe(samples: samples, sampleRate: 16_000)
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
        print("cohere short: \(String(format: "%.1f", Double(samples.count) / 16_000))s audio in \(String(format: "%.1f", seconds))s → \(text)")

        let lowered = text.lowercased()
        XCTAssertTrue(lowered.contains("dentist"), text)
        XCTAssertTrue(lowered.contains("tuesday"), text)
        XCTAssertTrue(lowered.contains("milk"), text)
    }

    func testChunksAndJoinsLongAudio() async throws {
        let service = try await Self.loadService()
        // AVSpeechSynthesizer.write stops delivering buffers partway through a
        // long utterance, so synthesize sentence by sentence with a short pause
        // between them (which also gives the chunker real silence to cut at).
        var samples: [Float] = []
        for sentence in Self.longText.split(separator: ".") where !sentence.trimmingCharacters(in: .whitespaces).isEmpty {
            samples += await SpeechTestAudio.synthesizeSpeech(String(sentence) + ".", sampleRate: 16_000)
            samples += [Float](repeating: 0, count: 4_800)
        }
        try XCTSkipUnless(
            samples.count > CohereAudioChunker.maxChunkSamples,
            "Synthesized clip too short to chunk (\(Double(samples.count) / 16_000)s)"
        )
        XCTAssertEqual(CohereAudioChunker.split(samples).count, 2)

        let started = DispatchTime.now()
        let text = try await service.transcribe(samples: samples, sampleRate: 16_000)
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
        print("cohere long: \(String(format: "%.1f", Double(samples.count) / 16_000))s audio in \(String(format: "%.1f", seconds))s → \(text)")

        let lowered = text.lowercased()
        XCTAssertTrue(lowered.contains("quick brown fox"), text)
        XCTAssertTrue(lowered.contains("quietest point"), text)
        XCTAssertTrue(lowered.contains("rather than one"), text)
    }

    func testRejectsNon16kAudio() async throws {
        let service = try await Self.loadService()
        do {
            _ = try await service.transcribe(samples: [Float](repeating: 0, count: 48_000), sampleRate: 48_000)
            XCTFail("Expected unsupportedSampleRate")
        } catch CohereTranscriptionService.ServiceError.unsupportedSampleRate(48_000) {
            // Expected.
        }
    }
}
