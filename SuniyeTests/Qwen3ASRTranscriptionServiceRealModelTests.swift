import XCTest
@testable import Suniye

/// Opt-in end-to-end check of the Qwen3-ASR engine against the real 2.5 GB model
/// and the real llama-server: decodes a short utterance from 48 kHz capture,
/// rejects silence, and decodes a > 90 s clip so the chunk-and-join path runs.
/// Skipped unless enabled, so CI (which has no model) stays fast.
///
/// Run it:
///   TEST_RUNNER_SUNIYE_RUN_QWEN3_ASR_TESTS=1 \
///   [TEST_RUNNER_SUNIYE_QWEN3_ASR_MODEL_DIR=/path/to/gguf-dir] \
///   [TEST_RUNNER_SUNIYE_LLAMA_SERVER_PATH=/path/to/llama-server] \
///   xcodebuild test -project Suniye.xcodeproj -scheme Suniye \
///     -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData \
///     -only-testing:SuniyeTests/Qwen3ASRTranscriptionServiceRealModelTests \
///     ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
final class Qwen3ASRTranscriptionServiceRealModelTests: XCTestCase {
    private static let shortText = "Please schedule the dentist appointment for Tuesday at three thirty, and remind me to buy milk on the way home."

    static func loadService() async throws -> Qwen3ASRTranscriptionService {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SUNIYE_RUN_QWEN3_ASR_TESTS"] == "1",
            "Set SUNIYE_RUN_QWEN3_ASR_TESTS=1 to run the Qwen3-ASR real-model tests"
        )
        try XCTSkipUnless(LlamaServer.locateExecutable() != nil, "No llama-server helper; set SUNIYE_LLAMA_SERVER_PATH")

        let service = Qwen3ASRTranscriptionService()
        try await service.loadModel(config: try config())
        return service
    }

    static func config() throws -> RecognizerConfig {
        guard let directory = ProcessInfo.processInfo.environment["SUNIYE_QWEN3_ASR_MODEL_DIR"] else {
            let manager = ModelManager()
            try XCTSkipUnless(manager.isInstalled(.qwen3ASR17B), "Qwen3-ASR 1.7B is not installed")
            return try manager.makeRecognizerConfig(for: .qwen3ASR17B)
        }
        let manifest = ASRModelCatalog.entry(for: .qwen3ASR17B).manifest
        return RecognizerConfig(
            modelID: .qwen3ASR17B,
            family: .qwen3ASR,
            tokensPath: "\(directory)/\(manifest.tokens)",
            numThreads: 4,
            encoderPath: "\(directory)/\(manifest.encoder!)",
            modelPath: "\(directory)/\(manifest.model!)"
        )
    }

    func testTranscribesShortUtteranceFromCaptureRate() async throws {
        let service = try await Self.loadService()
        let samples = await SpeechTestAudio.synthesizeSpeech(Self.shortText, sampleRate: 48_000)
        try XCTSkipUnless(samples.count > 48_000, "Speech synthesis unavailable")

        let started = DispatchTime.now()
        let text = try await service.transcribe(samples: samples, sampleRate: 48_000)
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
        print("qwen3-asr short: \(String(format: "%.1f", Double(samples.count) / 48_000))s audio in \(String(format: "%.2f", seconds))s → \(text)")

        let lowered = text.lowercased()
        XCTAssertTrue(lowered.contains("dentist"), text)
        XCTAssertTrue(lowered.contains("tuesday"), text)
        XCTAssertTrue(lowered.contains("milk"), text)
        await service.unloadModel()
    }

    func testSilenceIsNeverDecoded() async throws {
        let service = try await Self.loadService()

        let text = try await service.transcribe(samples: [Float](repeating: 0, count: 48_000), sampleRate: 48_000)

        XCTAssertEqual(text, "")
        await service.unloadModel()
    }

    func testChunksAndJoinsLongAudio() async throws {
        let service = try await Self.loadService()
        // AVSpeechSynthesizer.write stops delivering buffers partway through a long
        // utterance, so synthesize sentence by sentence with a short pause between.
        var samples: [Float] = []
        for (sentence, _) in Self.longDictation {
            samples += await SpeechTestAudio.synthesizeSpeech(sentence, sampleRate: 16_000)
            samples += [Float](repeating: 0, count: 4_800)
        }
        try XCTSkipUnless(
            Qwen3ASR.chunker.split(samples).count >= 2,
            "Synthesized clip too short to chunk (\(Double(samples.count) / 16_000)s)"
        )

        let started = DispatchTime.now()
        let text = try await service.transcribe(samples: samples, sampleRate: 16_000)
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
        print("qwen3-asr long: \(String(format: "%.1f", Double(samples.count) / 16_000))s audio in \(String(format: "%.2f", seconds))s → \(text)")

        let lowered = text.lowercased()
        for (_, keyword) in Self.longDictation {
            XCTAssertTrue(lowered.contains(keyword), "missing \"\(keyword)\" in: \(text)")
        }
        await service.unloadModel()
    }

    /// Distinct sentences, each with a keyword that must survive chunking: long
    /// enough (> 90 s spoken) to need two requests.
    private static let longDictation: [(String, String)] = [
        ("On Monday morning the team reviewed the quarterly budget and agreed to cut travel costs.", "budget"),
        ("Afterwards, Maria ordered pancakes and coffee for everyone in the conference room.", "pancakes"),
        ("The new office in Lisbon will open next spring with space for forty engineers.", "lisbon"),
        ("Our customers asked for a dark theme, so the designers sketched three options.", "designers"),
        ("Remember to water the tomato plants on the balcony before the weekend trip.", "tomato"),
        ("The library closes early on Fridays, so return the history books by noon.", "library"),
        ("A storm is expected tonight, and the ferry to the island has been cancelled.", "ferry"),
        ("Please send the signed contract to the lawyer and keep a copy for our records.", "contract"),
        ("The bakery on the corner sells the best cinnamon rolls in the whole city.", "cinnamon"),
        ("During the concert, the violinist played a piece that nobody had heard before.", "violinist"),
        ("My grandfather still repairs old radios in the garage every Sunday afternoon.", "radios"),
        ("The marathon route passes the river, the old cathedral, and the central market.", "marathon"),
        ("We should book the hotel for the conference before the prices go up again.", "hotel"),
        ("The children built a sandcastle with towers, a moat, and a tiny wooden bridge.", "sandcastle"),
        ("The museum added a new wing for modern sculpture and photography last year.", "sculpture"),
        ("Before the flight, check that your passport is valid for at least six months.", "passport"),
        ("The farmer harvested pumpkins early because the first frost arrived in October.", "pumpkins"),
        ("Our neighbor plays the trumpet every night, which the dog does not appreciate.", "trumpet"),
        ("Finally, schedule a meeting with the accountant to review the tax documents.", "accountant"),
        ("Thank you for listening, and enjoy the rest of your evening with your family.", "evening"),
    ]
}
