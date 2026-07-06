import XCTest
@testable import SuniyeAnalytics

final class AnalyticsEventEncodingTests: XCTestCase {
    func testEventNames() {
        XCTAssertEqual(AnalyticsEvent.appLaunch(device: device, settings: SettingsSnapshot(), firstLaunch: true).name, "app_launch")
        XCTAssertEqual(AnalyticsEvent.dictationCompleted(TestFixtures.sampleMetrics).name, "dictation_completed")
        XCTAssertEqual(AnalyticsEvent.error(type: .transcription, code: .timeout).name, "error")
    }

    func testDictationCompletedProps() {
        let props = AnalyticsEvent.dictationCompleted(TestFixtures.sampleMetrics).props
        XCTAssertEqual(props["word_count"], .int(42))
        XCTAssertEqual(props["char_count"], .int(213))
        XCTAssertEqual(props["asr_model"], .label("parakeet-v3"))
        XCTAssertEqual(props["was_llm_polished"], .bool(true))
        XCTAssertEqual(props["target_category"], .label("editor"))
        XCTAssertEqual(props["lat_end_to_end"], .int(512))
        // Latency stages that did not run are omitted, not zeroed.
        XCTAssertNil(props["lat_asr_to_llm"])
    }

    func testDictationEditedEvent() {
        let event = AnalyticsEvent.dictationEdited(editRateBucket: 30)
        XCTAssertEqual(event.name, "dictation_edited")
        XCTAssertEqual(event.props["edit_rate_bucket"], .int(30))
    }

    func testAudioQualityMergedIntoDictationProps() {
        var metrics = TestFixtures.sampleMetrics
        metrics.audio = DictationMetrics.AudioQuality(
            backend: SafeLabel("core_audio"), inputTransport: SafeLabel("usb"),
            inputSampleRate: 48_000, inputChannels: 1, echoCancellationEffective: true
        )
        let props = AnalyticsEvent.dictationCompleted(metrics).props
        XCTAssertEqual(props["audio_backend"], .label("core_audio"))
        XCTAssertEqual(props["input_sample_rate"], .int(48_000))
        XCTAssertEqual(props["input_channels"], .int(1))
        XCTAssertEqual(props["aec_effective"], .bool(true))
        // Unset audio fields are omitted, not zeroed.
        XCTAssertNil(props["aec_requested"])
    }

    func testAppLaunchMergesDeviceAndSettings() {
        let settings = SettingsSnapshot(["magic_format_enabled": .bool(true), "asr_model": .label("parakeet")])
        let props = AnalyticsEvent.appLaunch(device: device, settings: settings, firstLaunch: false).props
        XCTAssertEqual(props["chip"], .label("apple-m3-pro"))
        XCTAssertEqual(props["ram_gb"], .int(36))
        XCTAssertEqual(props["setting_magic_format_enabled"], .bool(true))
        XCTAssertEqual(props["first_launch"], .bool(false))
    }

    func testEncodedEventRoundTrips() throws {
        let event = EncodedEvent(event: .dictationCompleted(TestFixtures.sampleMetrics), eventID: "e1", eventTS: 1700, sessionID: "s1")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(EncodedEvent.self, from: data)
        XCTAssertEqual(decoded, event)

        // Wire keys are snake_case.
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"event_id\""))
        XCTAssertTrue(json.contains("\"event_ts\""))
        XCTAssertTrue(json.contains("\"session_id\""))
    }

    func testBatchEnvelopeKeys() throws {
        let event = EncodedEvent(event: .dictationEmpty, eventID: "e", eventTS: 1, sessionID: "s")
        let batch = AnalyticsBatch(
            schemaVersion: analyticsSchemaVersion, installID: "i", appVersion: "0.0.8",
            build: "8", channel: "stable", isDebug: false, sentAt: 123, events: [event]
        )
        let json = String(data: try JSONEncoder().encode(batch), encoding: .utf8)!
        for key in ["\"schema_version\"", "\"install_id\"", "\"app_version\"", "\"is_debug\"", "\"sent_at\"", "\"events\""] {
            XCTAssertTrue(json.contains(key), "missing \(key)")
        }
    }

    func testFreeTextCannotLeakThroughSafeLabel() {
        // Even if the app hands a sentence where a model id is expected, the
        // encoded value is a short slug — no spaces, no original words intact.
        let metrics = DictationMetrics(
            wordCount: 1, charCount: 1, audioDurationMs: 1,
            source: .hotkey, destination: .systemInsertion,
            asrModel: SafeLabel("the secret password is hunter2"),
            asrFamily: SafeLabel("x"), language: SafeLabel("en"), wasLLMPolished: false,
            insertionMethod: .clipboard, targetCategory: .other, latency: .init()
        )
        guard case let .label(value)? = metrics.props["asr_model"] else { return XCTFail() }
        XCTAssertFalse(value.contains(" "))
        XCTAssertLessThanOrEqual(value.count, SafeLabel.maxLength)
    }

    private var device: DeviceProfile {
        DeviceProfile(
            osVersion: SafeLabel("15.5"), arch: SafeLabel("arm64"),
            macModel: SafeLabel("mac15-3"), chip: SafeLabel("Apple M3 Pro"),
            ramGB: 36, cpuCores: 12, perfCores: 6, effCores: 6, language: SafeLabel("en")
        )
    }
}
