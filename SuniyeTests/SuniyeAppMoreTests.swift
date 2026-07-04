import Foundation
import XCTest
@testable import Suniye

final class SuniyeAppMoreTests: XCTestCase {
    /// ProcessInfo whose environment hides the XCTest marker so the
    /// non-test branches of the runtime-service gates are exercised.
    private final class EmptyEnvironmentProcessInfo: ProcessInfo, @unchecked Sendable {
        override var environment: [String: String] { [:] }
    }

    func testRuntimeServiceGatesAreClosedUnderXCTest() {
        let processInfo = ProcessInfo.processInfo

        XCTAssertTrue(processInfo.isRunningUnderXCTest)
        XCTAssertFalse(processInfo.shouldStartUpdateController)
        XCTAssertFalse(processInfo.shouldStartRuntimeServices)
    }

    func testRuntimeServiceGatesOpenOutsideXCTestWithoutE2EArguments() {
        let processInfo = EmptyEnvironmentProcessInfo()

        XCTAssertFalse(processInfo.isRunningUnderXCTest)
        // The test runner's command line has no --e2e- arguments, so both
        // gates fall through to their argument checks and open.
        XCTAssertTrue(processInfo.shouldStartUpdateController)
        XCTAssertTrue(processInfo.shouldStartRuntimeServices)
    }
}
