import Foundation
import XCTest
@testable import SuniyeAnalytics

/// Records uploads and returns a scriptable outcome.
final class MockUploader: AnalyticsUploading, @unchecked Sendable {
    private let lock = NSLock()
    private var _outcome: UploadOutcome
    private var _batches: [AnalyticsBatch] = []

    init(outcome: UploadOutcome = .accepted(nil)) { self._outcome = outcome }

    var outcome: UploadOutcome {
        get { lock.lock(); defer { lock.unlock() }; return _outcome }
        set { lock.lock(); _outcome = newValue; lock.unlock() }
    }

    var batches: [AnalyticsBatch] {
        lock.lock(); defer { lock.unlock() }; return _batches
    }

    var uploadedEventCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _batches.reduce(0) { $0 + $1.events.count }
    }

    func upload(_ batch: AnalyticsBatch) async -> UploadOutcome {
        lock.lock(); _batches.append(batch); let outcome = _outcome; lock.unlock()
        return outcome
    }
}

/// Deterministic, thread-safe clock.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { current = start }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }
}

/// Monotonic, thread-safe id generator for stable assertions.
final class TestIDGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> String { lock.lock(); defer { lock.unlock() }; n += 1; return "id-\(n)" }
}

enum TestFixtures {
    static func identity(isDebug: Bool = false, device: DeviceProfile? = nil) -> AnalyticsIdentity {
        AnalyticsIdentity(installID: "install-1", appVersion: "0.0.8", build: "8", channel: "stable", isDebug: isDebug, device: device)
    }

    static var sampleDevice: DeviceProfile {
        DeviceProfile(
            osVersion: SafeLabel("15.5"), arch: SafeLabel("arm64"),
            macModel: SafeLabel("mac15-3"), chip: SafeLabel("apple-m3-pro"),
            ramGB: 36, cpuCores: 12, perfCores: 6, effCores: 6, language: SafeLabel("en")
        )
    }

    static func tempQueueURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-analytics-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("queue.jsonl")
    }

    static func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "suniye.analytics.test.\(UUID().uuidString)")!
    }

    static var sampleMetrics: DictationMetrics {
        DictationMetrics(
            wordCount: 42, charCount: 213, audioDurationMs: 4200,
            source: .hotkey, destination: .systemInsertion,
            asrModel: SafeLabel("parakeet-v3"), asrFamily: SafeLabel("nemo_transducer"),
            language: SafeLabel("en"), wasLLMPolished: true,
            cleanupProvider: .localGemma, cleanupModel: SafeLabel("gemma-3-4b"),
            cleanupFallbackReason: nil,
            insertionMethod: .directAX, targetCategory: .editor,
            latency: .init(triggerToCaptureMs: 40, asrProcessingMs: 280, llmTotalMs: 190, insertMs: 25, endToEndMs: 512)
        )
    }
}
