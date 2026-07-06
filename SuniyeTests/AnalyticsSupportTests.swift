import XCTest
import SuniyeAnalytics
@testable import Suniye

final class AnalyticsSupportTests: XCTestCase {
    func testBucketRAMRoundsToTiers() {
        XCTAssertEqual(DeviceProfileReader.bucketRAM(16 * 1_073_741_824), 16)
        XCTAssertEqual(DeviceProfileReader.bucketRAM(36 * 1_073_741_824), 36)
        // 35 GB rounds up to the nearest standard tier (36).
        XCTAssertEqual(DeviceProfileReader.bucketRAM(35 * 1_073_741_824), 36)
        // 30 GB rounds to 32.
        XCTAssertEqual(DeviceProfileReader.bucketRAM(30 * 1_073_741_824), 32)
        XCTAssertEqual(DeviceProfileReader.bucketRAM(0), 0)
        XCTAssertEqual(DeviceProfileReader.bucketRAM(nil), 0)
    }

    func testDeviceProfileReadsRealHardware() {
        let profile = DeviceProfileReader.read()
        XCTAssertGreaterThan(profile.cpuCores, 0)
        XCTAssertGreaterThan(profile.ramGB, 0)
        XCTAssertFalse(profile.chip.value.isEmpty)
        XCTAssertFalse(profile.macModel.value.isEmpty)
    }

    func testTargetCategoryMapping() {
        XCTAssertEqual(TargetCategoryMapper.category(for: "com.apple.mail"), .email)
        XCTAssertEqual(TargetCategoryMapper.category(for: "com.microsoft.VSCode"), .ide)
        XCTAssertEqual(TargetCategoryMapper.category(for: "com.googlecode.iterm2"), .terminal)
        XCTAssertEqual(TargetCategoryMapper.category(for: "com.apple.Safari"), .browser)
        XCTAssertEqual(TargetCategoryMapper.category(for: "com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(TargetCategoryMapper.category(for: "md.obsidian"), .notes)
        XCTAssertEqual(TargetCategoryMapper.category(for: "com.unknown.app"), .other)
        XCTAssertEqual(TargetCategoryMapper.category(for: nil), .other)
    }

    func testCleanupProviderMapping() {
        XCTAssertEqual(AnalyticsMapping.cleanupProvider(.appleFoundationModels), .appleFoundationModels)
        XCTAssertEqual(AnalyticsMapping.cleanupProvider(.localGemma), .localGemma)
        XCTAssertEqual(AnalyticsMapping.cleanupProvider(.openAICompatible), .openAICompatible)
        XCTAssertEqual(AnalyticsMapping.cleanupProvider(.automatic), .automatic)
    }

    func testAudioOutcomeMapping() {
        XCTAssertEqual(AnalyticsMapping.audioOutcome(.complete), .complete)
        XCTAssertEqual(AnalyticsMapping.audioOutcome(.silent), .silent)
        XCTAssertEqual(AnalyticsMapping.audioOutcome(.bufferOverflow), .bufferOverflow)
        XCTAssertEqual(AnalyticsMapping.audioOutcome(.interrupted(.inputMuted)), .interrupted)
    }

    func testInterruptionReasonMappingIsLossless() {
        // Every source case maps to a distinct reason (no silent bucketing).
        XCTAssertEqual(AnalyticsMapping.interruptionReason(.inputMuted), .inputMuted)
        XCTAssertEqual(AnalyticsMapping.interruptionReason(.maximumDurationReached), .maximumDurationReached)
        XCTAssertEqual(AnalyticsMapping.interruptionReason(.deviceUnavailable), .deviceUnavailable)
        XCTAssertEqual(AnalyticsMapping.interruptionReason(.noAudioArriving), .noAudioArriving)
        XCTAssertEqual(AnalyticsMapping.interruptionReason(.engineConfigurationChanged), .engineConfigChanged)
    }

    func testDictationTimingComputesDeltas() {
        var timing = DictationTiming()
        let base = DispatchTime(uptimeNanoseconds: 1_000_000_000)
        timing.stopped = base
        timing.asrStart = base
        timing.asrEnd = DispatchTime(uptimeNanoseconds: base.uptimeNanoseconds + 280_000_000)
        timing.inserted = DispatchTime(uptimeNanoseconds: base.uptimeNanoseconds + 500_000_000)

        let latency = timing.latency()
        XCTAssertEqual(latency.asrProcessingMs, 280)
        XCTAssertEqual(latency.endToEndMs, 500)
        XCTAssertNil(latency.llmTotalMs) // not marked
    }
}
