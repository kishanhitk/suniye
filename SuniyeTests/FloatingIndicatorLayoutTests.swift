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

    func testListeningPanelMatchesPillWithoutPreviewAndBubbleGeometryIsFixed() {
        XCTAssertEqual(
            FloatingIndicatorMetrics.listeningPanelSize(preview: .off),
            FloatingIndicatorMetrics.listeningPillSize
        )

        // Fixed reservation: `.pending` and any preview text yield identical
        // panel geometry, so the panel never resizes mid-recording and the
        // layout cannot jitter as the transcript grows tick to tick. The
        // reservation includes room for the bubble's shadow so the window edge
        // cannot clip it.
        let expected = CGSize(
            width: max(
                FloatingIndicatorMetrics.listeningPillSize.width,
                FloatingIndicatorMetrics.previewBubbleSize.width
                    + FloatingIndicatorMetrics.previewShadowPadding * 2
            ),
            height: FloatingIndicatorMetrics.listeningPillSize.height
                + FloatingIndicatorMetrics.previewBubbleGap
                + FloatingIndicatorMetrics.previewBubbleSize.height
                + FloatingIndicatorMetrics.previewShadowPadding
        )
        let previews: [FloatingIndicatorState.PreviewState] = [
            .pending,
            .text("hi"),
            .text(String(repeating: "x", count: 200))
        ]
        for preview in previews {
            XCTAssertEqual(FloatingIndicatorMetrics.listeningPanelSize(preview: preview), expected)
        }
    }

    func testPreviewBubbleGrowsPanelUpwardWithoutMovingThePill() {
        let visibleFrame = NSRect(x: 0, y: 32, width: 1440, height: 900)
        let placement = FloatingIndicatorPlacement(centerXRatio: 0.5, bottomYRatio: 0.1)
        let pillOnly = FloatingIndicatorMetrics.listeningPanelSize(preview: .off)
        let withBubble = FloatingIndicatorMetrics.listeningPanelSize(preview: .pending)

        let pillFrame = FloatingIndicatorLayout.frame(
            for: NSSize(width: pillOnly.width, height: pillOnly.height),
            in: visibleFrame,
            placement: placement,
            bottomMargin: 28
        )
        let bubbleFrame = FloatingIndicatorLayout.frame(
            for: NSSize(width: withBubble.width, height: withBubble.height),
            in: visibleFrame,
            placement: placement,
            bottomMargin: 28
        )

        // Bottom edge and horizontal center are anchored; only the top rises.
        // The panel content is bottom-aligned, so the pill itself stays put.
        XCTAssertEqual(bubbleFrame.minY, pillFrame.minY, accuracy: 0.001)
        XCTAssertEqual(bubbleFrame.midX, pillFrame.midX, accuracy: 0.001)
        XCTAssertEqual(
            bubbleFrame.maxY - pillFrame.maxY,
            FloatingIndicatorMetrics.previewBubbleGap
                + FloatingIndicatorMetrics.previewBubbleSize.height
                + FloatingIndicatorMetrics.previewShadowPadding,
            accuracy: 0.001
        )
    }

    func testPreviewTailKeepsShortTextIntact() {
        XCTAssertEqual(FloatingIndicatorMetrics.previewTail("hello world"), "hello world")
        XCTAssertEqual(FloatingIndicatorMetrics.previewTail("  padded  "), "padded")
        XCTAssertEqual(FloatingIndicatorMetrics.previewTail(""), "")
    }

    func testPreviewTailTruncatesLongTextToSuffixWithoutEllipsis() {
        let maxCharacters = FloatingIndicatorMetrics.previewTailMaxCharacters
        let text = String(repeating: "a", count: 40) + String(repeating: "b", count: maxCharacters)
        let tail = FloatingIndicatorMetrics.previewTail(text)

        // No leading ellipsis: the bubble fades older text out at the top, so a
        // marker would only double up with the fade.
        XCTAssertEqual(tail, String(repeating: "b", count: maxCharacters))
        XCTAssertEqual(tail.count, maxCharacters)
        XCTAssertFalse(tail.hasPrefix("…"))
    }
}
