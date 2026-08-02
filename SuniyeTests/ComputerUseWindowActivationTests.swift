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
}
