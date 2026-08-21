import AVFoundation
import XCTest
@testable import Suniye

/// Opt-in driver for `evals/asr-compare`: runs every installed speech model over
/// every WAV in a directory and writes per-clip latency + transcript to JSON for
/// side-by-side human review. Skips unless pointed at a clips directory:
///
///   TEST_RUNNER_SUNIYE_ASR_COMPARE_DIR=/abs/path/to/clips \
///   xcodebuild test -project Suniye.xcodeproj -scheme Suniye \
///     -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData \
///     -only-testing:SuniyeTests/ASRModelComparisonTests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
///
/// Output: `<dir>/results.json`. Audio is fed at the file's own sample rate so each
/// engine's resampling is measured exactly as in the app.
final class ASRModelComparisonTests: XCTestCase {
    private struct Clip: Encodable {
        let file: String
        let seconds: Double
    }

    private struct Decode: Encodable {
        let file: String
        let ms: Int
        let text: String
        let error: String?
    }

    private struct ModelRun: Encodable {
        let id: String
        let name: String
        let loadMs: Int
        let results: [Decode]
    }

    private struct Report: Encodable {
        let generatedAt: String
        let machine: String
        let clips: [Clip]
        let models: [ModelRun]
    }

    func testCompareInstalledModelsOverClips() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SUNIYE_ASR_COMPARE_DIR"] else {
            throw XCTSkip("Set SUNIYE_ASR_COMPARE_DIR to a directory of WAV clips")
        }
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.lowercased().hasSuffix(".wav") }
            .sorted()
        try XCTSkipIf(files.isEmpty, "No .wav clips in \(directory)")

        // Keep each clip at its recorded rate: that is what the capture path hands the engines.
        var clips: [(name: String, samples: [Float], sampleRate: Int)] = []
        for file in files {
            let url = directoryURL.appendingPathComponent(file)
            let rate = try Self.sampleRate(of: url)
            clips.append((file, try SpeechTestAudio.loadWAV(path: url.path, sampleRate: Double(rate)), rate))
        }

        let manager = ModelManager()
        var candidates = manager.installedModels()
        if manager.isInstalled(.appleSpeech), await manager.isSystemManagedAssetInstalled(.appleSpeech) {
            candidates.append(.appleSpeech)
        }
        try XCTSkipIf(candidates.isEmpty, "No speech models installed")

        let router = RoutingTranscriptionService()
        var models: [ModelRun] = []
        for modelID in candidates {
            let entry = ASRModelCatalog.entry(for: modelID)
            let loadStarted = DispatchTime.now()
            do {
                try await router.loadModel(config: try manager.makeRecognizerConfig(for: modelID))
            } catch {
                models.append(ModelRun(id: modelID.rawValue, name: entry.displayName, loadMs: -1, results: [
                    Decode(file: "", ms: -1, text: "", error: "load failed: \(error.localizedDescription)")
                ]))
                continue
            }
            let loadMs = Self.elapsedMs(since: loadStarted)

            // One discarded warm-up so the numbers are steady-state, not first-run.
            if let first = clips.first {
                _ = try? await router.transcribe(samples: first.samples, sampleRate: first.sampleRate)
            }

            var results: [Decode] = []
            for clip in clips {
                let started = DispatchTime.now()
                do {
                    let text = try await router.transcribe(samples: clip.samples, sampleRate: clip.sampleRate)
                    results.append(Decode(file: clip.name, ms: Self.elapsedMs(since: started), text: text, error: nil))
                } catch {
                    results.append(Decode(file: clip.name, ms: Self.elapsedMs(since: started), text: "", error: error.localizedDescription))
                }
            }
            models.append(ModelRun(id: modelID.rawValue, name: entry.displayName, loadMs: loadMs, results: results))
            print("asr-compare: \(entry.displayName) load=\(loadMs)ms " + results.map { "\($0.file)=\($0.ms)ms" }.joined(separator: " "))
        }
        await router.unloadModel()

        let report = Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            machine: Self.machineName(),
            clips: clips.map { Clip(file: $0.name, seconds: Double($0.samples.count) / Double($0.sampleRate)) },
            models: models
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = directoryURL.appendingPathComponent("results.json")
        try encoder.encode(report).write(to: output)
        print("asr-compare: wrote \(output.path)")
    }

    private static func elapsedMs(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    private static func sampleRate(of url: URL) throws -> Int {
        Int(try AVAudioFile(forReading: url).processingFormat.sampleRate.rounded())
    }

    private static func machineName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
