import XCTest
@testable import Suniye

/// Covers the live-preview additions to `FloatingIndicatorState`
/// (`layoutAnimationKey`, `PreviewState`) that are otherwise only exercised by
/// the render-only, coverage-excluded `FloatingIndicatorView`.
final class FloatingIndicatorAnimationKeyTests: XCTestCase {
    private let levels = Array(repeating: Float(0), count: AudioLevelMeter.bandCount)

    // MARK: PreviewState

    func testPreviewStateReservesBubbleSpaceOnlyWhenNotOff() {
        XCTAssertFalse(FloatingIndicatorState.PreviewState.off.reservesBubbleSpace)
        XCTAssertTrue(FloatingIndicatorState.PreviewState.pending.reservesBubbleSpace)
        XCTAssertTrue(FloatingIndicatorState.PreviewState.text("hi").reservesBubbleSpace)
    }

    func testPreviewStateTextAccessor() {
        XCTAssertNil(FloatingIndicatorState.PreviewState.off.text)
        XCTAssertNil(FloatingIndicatorState.PreviewState.pending.text)
        XCTAssertEqual(FloatingIndicatorState.PreviewState.text("hello").text, "hello")
    }

    // MARK: layoutAnimationKey — excludes per-tick churn (levels, preview text)

    func testLayoutAnimationKeyMapsEachState() {
        XCTAssertEqual(FloatingIndicatorState.idle.layoutAnimationKey, .idle)
        XCTAssertEqual(FloatingIndicatorState.hover.layoutAnimationKey, .hover)
        XCTAssertEqual(
            FloatingIndicatorState.listening(levels: levels, source: .editHotkey).layoutAnimationKey,
            .listening(source: .editHotkey)
        )
        XCTAssertEqual(
            FloatingIndicatorState.processing(message: "Transcribing…").layoutAnimationKey,
            .processing(message: "Transcribing…")
        )
        XCTAssertEqual(
            FloatingIndicatorState.error(message: "boom").layoutAnimationKey,
            .error(message: "boom")
        )
    }

    func testLayoutAnimationKeyIgnoresLevelsAndPreviewText() {
        let quiet = FloatingIndicatorState.listening(levels: levels, source: .manual, preview: .pending)
        let loud = FloatingIndicatorState.listening(
            levels: Array(repeating: Float(0.9), count: AudioLevelMeter.bandCount),
            source: .manual,
            preview: .text("some words")
        )
        // Same pill layout: the key must not change on meter/preview churn, so
        // the layout spring doesn't re-fire every tick.
        XCTAssertEqual(quiet.layoutAnimationKey, loud.layoutAnimationKey)
    }

    func testLayoutAnimationKeyDistinguishesSource() {
        XCTAssertNotEqual(
            FloatingIndicatorState.listening(levels: levels, source: .manual).layoutAnimationKey,
            FloatingIndicatorState.listening(levels: levels, source: .editHotkey).layoutAnimationKey
        )
    }
}
