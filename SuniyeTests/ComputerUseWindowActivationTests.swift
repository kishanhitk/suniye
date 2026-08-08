import XCTest
@testable import Suniye

final class ComputerUseWindowActivationTests: XCTestCase {
    func testOwnProcessDoesNotUseReentrantAccessibilityRaise() {
        XCTAssertFalse(
            ComputerUseWindowActivationPolicy.shouldUseAccessibilityRaise(
                targetProcessIdentifier: 42,
                currentProcessIdentifier: 42
            )
        )
        XCTAssertTrue(
            ComputerUseWindowActivationPolicy.shouldUseAccessibilityRaise(
                targetProcessIdentifier: 42,
                currentProcessIdentifier: 84
            )
        )
    }

    func testAccessibilityRaiseCanRecoverARejectedApplicationActivation() {
        let target = makeTarget(processIdentifier: ProcessInfo.processInfo.processIdentifier + 1)
        let activator = SystemComputerUseWindowActivator(
            runningApplicationProvider: { _ in .current },
            applicationActivator: { _ in false },
            windowRaiser: { $0 == target }
        )

        XCTAssertTrue(activator.activate(target: target))
    }

    func testActivationFailsWhenNeitherApplicationNorWindowCanActivate() {
        let target = makeTarget(processIdentifier: ProcessInfo.processInfo.processIdentifier + 1)
        let activator = SystemComputerUseWindowActivator(
            runningApplicationProvider: { _ in .current },
            applicationActivator: { _ in false },
            windowRaiser: { _ in false }
        )

        XCTAssertFalse(activator.activate(target: target))
    }

    private func makeTarget(processIdentifier: Int32) -> ComputerUseTarget {
        ComputerUseTarget(
            application: ComputerUseApplication(
                id: "com.example.target",
                bundleIdentifier: "com.example.target",
                displayName: "Target",
                processIdentifier: processIdentifier,
                isRunning: true,
                isActive: false
            ),
            window: ComputerUseWindow(
                id: 42,
                title: "Target",
                ownerProcessIdentifier: processIdentifier,
                bounds: ComputerUseRect(x: 0, y: 0, width: 800, height: 600),
                layer: 0,
                isOnScreen: true,
                isKeyWindow: false
            )
        )
    }
}
