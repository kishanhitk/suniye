import AVFoundation
import XCTest
@testable import Suniye

/// Opt-in latency benchmark comparing the Parakeet (sherpa-onnx, CPU) and Apple Speech
/// (SpeechAnalyzer, Neural Engine) providers on the *same* audio.
///
/// Both engines run in batch mode (whole clip after recording stops), which is exactly how
/// the app dictates — so the numbers are the real per-utterance transcription latency, minus
/// capture teardown / Magic Format / text insertion.
///
/// Reproducible: the input is synthesized speech (no fixture to ship). Point
/// `SUNIYE_BENCH_WAV` at a recorded WAV for a fully real-audio measurement.
///
/// Run it (skips otherwise). NOTE: xcodebuild only forwards env vars to the test runner
/// when they carry a `TEST_RUNNER_` prefix, which it strips before the process sees them:
///   TEST_RUNNER_SUNIYE_RUN_ASR_BENCH=1 \
///   [TEST_RUNNER_SUNIYE_BENCH_WAV=/path/to/voice.wav] \
///   xcodebuild test \
///     -project Suniye.xcodeproj -scheme Suniye \
///     -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData \
///     -only-testing:SuniyeTests/ASRLatencyBenchmarkTests \
///     ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
final class ASRLatencyBenchmarkTests: XCTestCase {
    private static let iterations = 5

    private static let benchText = """
    The quick brown fox jumps over the lazy dog. Speech recognition has come a long way, \
    and running it entirely on device keeps your dictation private and fast. This sentence \
    exists only to give the transcriber a realistic amount of audio to process, roughly a \
    dozen seconds, so that the measured latency reflects a normal dictation rather than a \
    trivial one word utterance.
    """

    func testParakeetVsAppleLatency() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SUNIYE_RUN_ASR_BENCH"] == "1",
            "Set SUNIYE_RUN_ASR_BENCH=1 to run the ASR latency benchmark"
        )

        let sampleRate = 16_000
        let samples = try await Self.loadAudio(sampleRate: Double(sampleRate))
        let audioSeconds = Double(samples.count) / Double(sampleRate)
        try XCTSkipUnless(audioSeconds >= 3, "Synthesized audio too short (\(audioSeconds)s); TTS may be unavailable")

        var lines: [String] = []
        lines.append(String(format: "audio=%.1fs  iterations=%d (after 1 warm-up)", audioSeconds, Self.iterations))
        lines.append("engine                     p50(ms)  p90(ms)   RTF   transcript")

        if let parakeet = try await Self.loadParakeet() {
            let r = await Self.benchmark(parakeet, samples: samples, sampleRate: sampleRate)
            lines.append(Self.row("Parakeet v3 (sherpa/CPU)", r, audioSeconds))
        } else {
            lines.append("Parakeet v3 (sherpa/CPU)   — SKIPPED: model not installed")
        }

        if let apple = await Self.loadApple() {
            let r = await Self.benchmark(apple, samples: samples, sampleRate: sampleRate)
            lines.append(Self.row("Apple Speech (ANE)       ", r, audioSeconds))
        } else {
            lines.append("Apple Speech (ANE)         — SKIPPED: unavailable or asset not installed")
        }

        print("\n===== ASR latency benchmark =====")
        lines.forEach { print($0) }
        print("RTF = processing_time / audio_length  (lower is faster; <1 = faster than real-time)")
        print("Note: Parakeet runs on CPU, Apple on the Neural Engine — this is the real-world contrast.\n")
    }

    // MARK: - Timing

    private struct Result {
        let p50Milliseconds: Double
        let p90Milliseconds: Double
        let transcript: String
    }

    private static func benchmark(
        _ engine: TranscriptionServiceProtocol,
        samples: [Float],
        sampleRate: Int
    ) async -> Result {
        _ = try? await engine.transcribe(samples: samples, sampleRate: sampleRate) // warm-up (discarded)

        var timings: [Double] = []
        var transcript = ""
        for _ in 0 ..< iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            let text = (try? await engine.transcribe(samples: samples, sampleRate: sampleRate)) ?? ""
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            timings.append(elapsedMs)
            transcript = text
        }
        timings.sort()
        let p50 = timings[timings.count / 2]
        let p90 = timings[min(timings.count - 1, Int((Double(timings.count) * 0.9).rounded(.down)))]
        return Result(p50Milliseconds: p50, p90Milliseconds: p90, transcript: transcript)
    }

    private static func row(_ name: String, _ r: Result, _ audioSeconds: Double) -> String {
        let rtf = (r.p50Milliseconds / 1000) / audioSeconds
        let preview = r.transcript.prefix(48)
        return String(format: "%-26@ %7.0f  %7.0f  %5.3f   \"%@…\"", name as NSString, r.p50Milliseconds, r.p90Milliseconds, rtf, String(preview) as NSString)
    }

    // MARK: - Engine loading

    private static func loadParakeet() async throws -> TranscriptionServiceProtocol? {
        let modelManager = ModelManager()
        guard modelManager.isInstalled(.parakeetV3) else { return nil }
        let config = try modelManager.makeRecognizerConfig(for: .parakeetV3)
        let service = TranscriptionService()
        try await service.loadModel(config: config)
        return service
    }

    private static func loadApple() async -> TranscriptionServiceProtocol? {
        guard AppleSpeechSupport.isAvailable, #available(macOS 26, *) else { return nil }
        guard await AppleSpeechAssetInstaller.isInstalled() else { return nil }
        let service = AppleSpeechTranscriptionService()
        do {
            try await service.loadModel(
                config: RecognizerConfig(modelID: .appleSpeech, family: .appleSpeech, tokensPath: "", numThreads: 1)
            )
            return service
        } catch {
            return nil
        }
    }

    // MARK: - Audio input (recorded WAV if provided, else synthesized speech)

    private static func loadAudio(sampleRate: Double) async throws -> [Float] {
        if let path = ProcessInfo.processInfo.environment["SUNIYE_BENCH_WAV"] {
            return try loadWAV(path: path, sampleRate: sampleRate)
        }
        return await synthesizeSpeech(benchText, sampleRate: sampleRate)
    }

    private static func loadWAV(path: String, sampleRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: source)
        return convert(source, to: target)
    }

    private static func synthesizeSpeech(_ text: String, sampleRate: Double) async -> [Float] {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            return []
        }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)

        var floats: [Float] = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !resumed { resumed = true; continuation.resume() }
                    return
                }
                floats.append(contentsOf: convert(pcm, to: target))
            }
        }
        _ = synthesizer // keep alive across the write callbacks
        return floats
    }

    /// One-shot convert a PCM buffer to the target format and return its mono float samples.
    private static func convert(_ input: AVAudioPCMBuffer, to target: AVAudioFormat) -> [Float] {
        if input.format == target {
            guard let channel = input.floatChannelData?[0] else { return [] }
            return Array(UnsafeBufferPointer(start: channel, count: Int(input.frameLength)))
        }
        guard let converter = AVAudioConverter(from: input.format, to: target) else { return [] }
        let capacity = AVAudioFrameCount((Double(input.frameLength) * target.sampleRate / input.format.sampleRate).rounded(.up)) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }

        var fed = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        guard let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
