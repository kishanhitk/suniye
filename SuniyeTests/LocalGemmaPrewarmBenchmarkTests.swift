import XCTest
@testable import Suniye

/// Opt-in latency benchmark for the local Gemma Magic Format path, through the real
/// `LocalGemmaPostProcessor` → `LocalGemmaLlamaCppClient` → bundled `llama-server`.
///
/// Measures what the user waits on after the model is already up: the first polish
/// after a prewarm (does the probe leave llama-server's prompt cache primed with the
/// real system-prompt prefix?) versus steady-state polishes.
///
/// Needs the Gemma model installed in Application Support and the bundled server:
///   TEST_RUNNER_SUNIYE_RUN_GEMMA_BENCH=1 \
///   TEST_RUNNER_SUNIYE_LLAMA_SERVER_PATH=$PWD/Suniye/LocalLLM/llama-server \
///   xcodebuild test \
///     -project Suniye.xcodeproj -scheme Suniye \
///     -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData \
///     -only-testing:SuniyeTests/LocalGemmaPrewarmBenchmarkTests \
///     ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
final class LocalGemmaPrewarmBenchmarkTests: XCTestCase {
    /// Cold cycles per run; override with SUNIYE_GEMMA_BENCH_CYCLES.
    private static let cycles = max(1, ProcessInfo.processInfo.environment["SUNIYE_GEMMA_BENCH_CYCLES"].flatMap(Int.init) ?? 3)

    private static let transcripts = [
        "okay so um the meeting got moved to thursday at three can you let uh sarah know and also we need to push the release by a week",
        "hey quick note to self buy milk eggs and bread and also call the dentist tomorrow morning before nine",
    ]

    func testFirstPolishAfterPrewarm() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SUNIYE_RUN_GEMMA_BENCH"] == "1",
            "Set SUNIYE_RUN_GEMMA_BENCH=1 to run the local Gemma prewarm benchmark"
        )

        let processor = LocalGemmaPostProcessor()
        try XCTSkipUnless(processor.availability.isAvailable, "Local Gemma unavailable: \(processor.availability.logValue)")

        let config = await MainActor.run { MagicFormatCoordinator.makeLocalGemmaConfig(settings: LLMSettings()) }
        var prewarmMs: [Double] = []
        var firstPolishMs: [Double] = []
        var steadyPolishMs: [Double] = []

        for _ in 0 ..< Self.cycles {
            await processor.stopRuntime()

            let prewarmStart = DispatchTime.now().uptimeNanoseconds
            await processor.prewarm(config: config)
            prewarmMs.append(Self.elapsedMs(since: prewarmStart))
            let isWarm = await processor.isRuntimeWarm()
            XCTAssertTrue(isWarm, "prewarm did not leave the runtime warm")

            let firstStart = DispatchTime.now().uptimeNanoseconds
            _ = try await processor.polish(text: Self.transcripts[0], config: config)
            firstPolishMs.append(Self.elapsedMs(since: firstStart))

            let steadyStart = DispatchTime.now().uptimeNanoseconds
            _ = try await processor.polish(text: Self.transcripts[1], config: config)
            steadyPolishMs.append(Self.elapsedMs(since: steadyStart))
        }
        await processor.stopRuntime()

        print("\n===== Local Gemma prewarm benchmark (\(Self.cycles) cold cycles) =====")
        print("stage                        min(ms)  p50(ms)  p90(ms)  max(ms)   all")
        print(Self.row("prewarm (spawn+load+probe)", prewarmMs))
        print(Self.row("first polish after prewarm", firstPolishMs))
        print(Self.row("steady-state polish", steadyPolishMs))
        print("first-polish minus steady = prompt-cache miss cost the user pays on the critical path\n")
    }

    private static func elapsedMs(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func row(_ name: String, _ values: [Double]) -> String {
        let sorted = values.sorted()
        let p90 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.9).rounded(.down)))]
        let all = values.map { String(format: "%.0f", $0) }.joined(separator: " ")
        return String(
            format: "%-28@ %7.0f  %7.0f  %7.0f  %7.0f   [%@]",
            name as NSString, sorted.first ?? 0, sorted[sorted.count / 2], p90, sorted.last ?? 0, all as NSString
        )
    }
}
