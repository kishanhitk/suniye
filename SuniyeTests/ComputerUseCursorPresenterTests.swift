import AppKit
import XCTest
@testable import Suniye

@MainActor
final class ComputerUseCursorPresenterTests: XCTestCase {
    func testQuartzPointsConvertIntoAppKitScreenCoordinates() {
        XCTAssertEqual(
            ComputerUseCursorCoordinateSpace.appKitPoint(
                fromQuartz: CGPoint(x: 200, y: 300),
                primaryScreenMaxY: 900
            ),
            CGPoint(x: 200, y: 600)
        )
    }

    func testCursorGlowBreathesWithinSubtleBounds() {
        let dimmest = ComputerUseCursorGlowAnimation.style(
            at: ComputerUseCursorGlowAnimation.cycleDuration * 0.75,
            reduceMotion: false
        )
        let brightest = ComputerUseCursorGlowAnimation.style(
            at: ComputerUseCursorGlowAnimation.cycleDuration * 0.25,
            reduceMotion: false
        )

        XCTAssertEqual(dimmest.scale, 0.98, accuracy: 0.0001)
        XCTAssertEqual(dimmest.opacity, 0.88, accuracy: 0.0001)
        XCTAssertEqual(brightest.scale, 1.02, accuracy: 0.0001)
        XCTAssertEqual(brightest.opacity, 1, accuracy: 0.0001)
    }

    func testCursorGlowIsStaticWhenReduceMotionIsEnabled() {
        let start = ComputerUseCursorGlowAnimation.style(at: 0, reduceMotion: true)
        let later = ComputerUseCursorGlowAnimation.style(at: 100, reduceMotion: true)

        XCTAssertEqual(start, later)
        XCTAssertEqual(start, ComputerUseCursorGlowStyle(scale: 1, opacity: 0.94))
    }

    func testSystemPresenterUsesVisibleNonActivatingOverlayWindow() async throws {
        let presenter = SystemComputerUseCursorPresenter()

        try await presenter.present(
            .click(
                point: CGPoint(x: 160, y: 160),
                target: .init(windowID: 9, processIdentifier: 42),
                mouseButton: .left,
                clickCount: 1
            )
        )

        let window = try XCTUnwrap(
            NSApp.windows.first(where: { $0.title == SystemComputerUseCursorPresenter.windowTitle })
        )
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)

        try await Task.sleep(for: .seconds(1.6))
        XCTAssertTrue(window.isVisible, "The cursor must persist between tool calls")

        presenter.endSession()
        XCTAssertFalse(window.isVisible)
    }
}
