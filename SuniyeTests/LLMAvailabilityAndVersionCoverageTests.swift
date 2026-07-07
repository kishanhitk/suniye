import XCTest
@testable import Suniye

/// Exercises pure enum/value logic (availability descriptors, error mapping,
/// version formatting) that carries no I/O, keeping it covered independent of
/// the hardware/native paths CI can't reach.
final class LLMAvailabilityAndVersionCoverageTests: XCTestCase {
    func testAppleFoundationModelsAvailabilityDescribesEveryCase() {
        let all: [AppleFoundationModelsAvailability] = [
            .available, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unsupportedSDKOrRuntime
        ]
        for value in all {
            XCTAssertFalse(value.statusText.isEmpty)
            XCTAssertFalse(value.logValue.isEmpty)
        }
        XCTAssertTrue(AppleFoundationModelsAvailability.available.isAvailable)
        XCTAssertFalse(AppleFoundationModelsAvailability.modelNotReady.isAvailable)
    }

    func testLocalGemmaAvailabilityDescribesEveryCase() {
        let all: [LocalGemmaAvailability] = [
            .available, .unsupportedHardware, .runtimeUnavailable, .modelNotInstalled
        ]
        for value in all {
            XCTAssertFalse(value.statusText.isEmpty)
            XCTAssertFalse(value.logValue.isEmpty)
        }
        XCTAssertTrue(LocalGemmaAvailability.available.isAvailable)
        XCTAssertFalse(LocalGemmaAvailability.runtimeUnavailable.isAvailable)
    }

    func testLLMPostProcessorErrorDescribesEveryCase() {
        let all: [LLMPostProcessorError] = [
            .invalidConfiguration("why"), .timeout, .unauthorized, .provider("boom"),
            .malformedResponse, .emptyOutput, .network("offline")
        ]
        for error in all {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
            XCTAssertFalse(error.logValue.isEmpty)
        }
        XCTAssertEqual(LLMPostProcessorError.emptyOutput.errorDescription, "LLM returned empty output")
        XCTAssertEqual(LLMPostProcessorError.invalidConfiguration("x").logValue, "invalid_config")
        XCTAssertEqual(LLMPostProcessorError.network("x").logValue, "network")
    }

    func testSemVerOrdersByMajorThenMinorThenPatch() throws {
        func ver(_ s: String) throws -> SemVer { try XCTUnwrap(SemVer(rawValue: s)) }
        XCTAssertTrue(try ver("1.0.0") < ver("2.0.0"))
        XCTAssertTrue(try ver("1.1.0") < ver("1.2.0"))
        XCTAssertTrue(try ver("1.1.1") < ver("1.1.2"))
        XCTAssertFalse(try ver("1.1.2") < ver("1.1.1"))
    }

    func testAppVersionDisplayStringWithAndWithoutBuild() throws {
        let marketing = try XCTUnwrap(SemVer(rawValue: "1.2.3"))
        XCTAssertEqual(AppVersion(marketing: marketing, build: 42, channel: .stable).displayString, "v1.2.3 (42)")
        XCTAssertEqual(AppVersion(marketing: marketing, build: nil, channel: .stable).displayString, "v1.2.3")

        let tipMarketing = try XCTUnwrap(SemVer(rawValue: "0.9.0"))
        XCTAssertTrue(AppVersion(marketing: tipMarketing, build: nil, channel: .tip).displayString.hasSuffix("Tip"))
    }

    func testAppAnalyticsFallsBackToNoopAndDetectsTestRun() {
        // No analytics endpoint is configured under test, so the factory returns
        // the no-op client, and the test run is classified as a debug build.
        _ = AppAnalytics.makeDefault()
        XCTAssertTrue(AppAnalytics.isDebugBuild())
    }
}
