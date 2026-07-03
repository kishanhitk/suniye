import AppKit
import XCTest
@testable import Suniye

final class FloatingIndicatorLayoutTests: XCTestCase {
    func testDefaultFrameUsesBottomCenter() {
        let visibleFrame = NSRect(x: 40, y: 24, width: 1200, height: 800)
        let size = NSSize(width: 128, height: 40)

        let frame = FloatingIndicatorLayout.defaultFrame(for: size, in: visibleFrame, bottomMargin: 28)

        XCTAssertEqual(frame.origin.x, 576, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 52, accuracy: 0.001)
        XCTAssertEqual(frame.width, 128, accuracy: 0.001)
        XCTAssertEqual(frame.height, 40, accuracy: 0.001)
    }

    func testPlacementRoundTripsFromFrame() {
        let visibleFrame = NSRect(x: 0, y: 32, width: 1440, height: 900)
        let originalFrame = NSRect(x: 300, y: 140, width: 116, height: 40)

        let placement = FloatingIndicatorLayout.placement(for: originalFrame, in: visibleFrame)
        let roundTrippedFrame = FloatingIndicatorLayout.frame(
            for: originalFrame.size,
            in: visibleFrame,
            placement: placement,
            bottomMargin: 28
        )

        XCTAssertEqual(roundTrippedFrame.origin.x, originalFrame.origin.x, accuracy: 0.001)
        XCTAssertEqual(roundTrippedFrame.origin.y, originalFrame.origin.y, accuracy: 0.001)
    }

    func testCustomPlacementClampsFrameInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 10, y: 10, width: 400, height: 300)
        let placement = FloatingIndicatorPlacement(centerXRatio: 1, bottomYRatio: 1)
        let size = NSSize(width: 272, height: 84)

        let frame = FloatingIndicatorLayout.frame(
            for: size,
            in: visibleFrame,
            placement: placement,
            bottomMargin: 28
        )

        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
    }

    func testListeningPillUsesFixedGeometryWheneverPreviewIsActive() {
        XCTAssertEqual(FloatingIndicatorMetrics.listeningPillWidth(preview: nil), 124)
        XCTAssertEqual(FloatingIndicatorMetrics.listeningPillHeight(preview: nil), 40)

        // Fixed capsule: any preview text yields identical geometry, so the pill
        // cannot jitter as the transcript grows tick to tick.
        for preview in ["hi", String(repeating: "x", count: 200)] {
            XCTAssertEqual(
                FloatingIndicatorMetrics.listeningPillWidth(preview: preview),
                FloatingIndicatorMetrics.previewCapsuleWidth
            )
            XCTAssertEqual(
                FloatingIndicatorMetrics.listeningPillHeight(preview: preview),
                FloatingIndicatorMetrics.previewCapsuleHeight
            )
        }
    }

    func testPreviewTailKeepsShortTextIntact() {
        XCTAssertEqual(FloatingIndicatorMetrics.previewTail("hello world"), "hello world")
        XCTAssertEqual(FloatingIndicatorMetrics.previewTail("  padded  "), "padded")
        XCTAssertEqual(FloatingIndicatorMetrics.previewTail(""), "")
    }

    func testPreviewTailTruncatesLongTextToSuffix() {
        let maxCharacters = FloatingIndicatorMetrics.previewTailMaxCharacters
        let text = String(repeating: "a", count: 40) + String(repeating: "b", count: maxCharacters)
        let tail = FloatingIndicatorMetrics.previewTail(text)

        XCTAssertEqual(tail, "…" + String(repeating: "b", count: maxCharacters))
        XCTAssertEqual(tail.count, maxCharacters + 1)
    }
}
