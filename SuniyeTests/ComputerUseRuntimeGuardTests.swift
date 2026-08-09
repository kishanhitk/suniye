import CoreGraphics
import XCTest
@testable import Suniye

final class ComputerUseRuntimeGuardTests: XCTestCase {
    func testScreenLockCheckerReadsLockedSessionFlag() {
        let checker = SystemComputerUseScreenLockChecker {
            ["CGSSessionScreenIsLocked": true]
        }

        XCTAssertTrue(checker.isScreenLocked())
    }

    func testScreenLockCheckerTreatsMissingFlagAsUnlocked() {
        let checker = SystemComputerUseScreenLockChecker {
            ["UnrelatedSessionValue": true]
        }

        XCTAssertFalse(checker.isScreenLocked())
    }

    func testPhysicalInputSamplerRetainsEachMonitoredCounter() {
        let sampler = SystemComputerUsePhysicalInputSampler { eventType in
            eventType.rawValue
        }

        XCTAssertEqual(
            sampler.snapshot().eventCounts,
            [
                CGEventType.leftMouseDown.rawValue,
                CGEventType.rightMouseDown.rawValue,
                CGEventType.otherMouseDown.rawValue,
                CGEventType.mouseMoved.rawValue,
                CGEventType.leftMouseDragged.rawValue,
                CGEventType.rightMouseDragged.rawValue,
                CGEventType.otherMouseDragged.rawValue,
                CGEventType.scrollWheel.rawValue,
                CGEventType.keyDown.rawValue,
                CGEventType.flagsChanged.rawValue,
            ]
        )
    }

    func testLoadingStateCheckerFindsNestedProgressIndicator() async {
        let accessibility = RuntimeGuardAccessibilityStub(
            result: .success(
                ComputerUseAXSnapshot(
                    roots: [
                        runtimeGuardNode(
                            role: "AXWindow",
                            children: [runtimeGuardNode(role: "AXProgressIndicator")]
                        ),
                    ]
                )
            )
        )
        let checker = SystemComputerUseLoadingStateChecker(accessibility: accessibility)

        let isLoading = await checker.isLoading(runtimeGuardTarget())

        XCTAssertTrue(isLoading)
        let requests = await accessibility.requests
        XCTAssertEqual(requests, [.init(processIdentifier: 123, windowOrdinal: 2)])
    }

    func testLoadingStateCheckerReturnsFalseWithoutIndicator() async {
        let accessibility = RuntimeGuardAccessibilityStub(
            result: .success(
                ComputerUseAXSnapshot(roots: [runtimeGuardNode(role: "AXWindow")])
            )
        )
        let checker = SystemComputerUseLoadingStateChecker(accessibility: accessibility)

        let isLoading = await checker.isLoading(runtimeGuardTarget())

        XCTAssertFalse(isLoading)
    }

    func testLoadingStateCheckerReturnsFalseWhenSnapshotFails() async {
        let accessibility = RuntimeGuardAccessibilityStub(
            result: .failure(RuntimeGuardTestError.snapshotFailed)
        )
        let checker = SystemComputerUseLoadingStateChecker(accessibility: accessibility)

        let isLoading = await checker.isLoading(runtimeGuardTarget())

        XCTAssertFalse(isLoading)
    }
}

private enum RuntimeGuardTestError: Error {
    case snapshotFailed
}

private actor RuntimeGuardAccessibilityStub: ComputerUseAccessibilitySnapshotProviding {
    struct Request: Equatable {
        let processIdentifier: Int32
        let windowOrdinal: Int
    }

    private(set) var requests: [Request] = []
    private let result: Result<ComputerUseAXSnapshot, Error>

    init(result: Result<ComputerUseAXSnapshot, Error>) {
        self.result = result
    }

    func snapshot(processIdentifier: Int32, windowOrdinal: Int) throws
        -> ComputerUseAXSnapshot
    {
        requests.append(.init(
            processIdentifier: processIdentifier,
            windowOrdinal: windowOrdinal
        ))
        return try result.get()
    }
}

private func runtimeGuardTarget() -> ComputerUseObservedTarget {
    ComputerUseObservedTarget(
        application: ComputerUseApplicationRecord(
            displayName: "Example",
            bundleIdentifier: "com.example.app",
            applicationURL: URL(fileURLWithPath: "/Applications/Example.app"),
            lastUsedDate: nil,
            useCount: nil,
            processIdentifier: 123,
            isFrontmost: false
        ),
        window: ComputerUseWindow(
            id: 99,
            ownerProcessIdentifier: 123,
            title: "Document",
            bounds: CGRect(x: 10, y: 20, width: 300, height: 200),
            layer: 0,
            isOnScreen: true,
            accessibilityOrdinal: 2,
            isFocused: false,
            isMain: false
        )
    )
}

private func runtimeGuardNode(
    role: String,
    children: [ComputerUseAXNode] = []
) -> ComputerUseAXNode {
    ComputerUseAXNode(
        role: role,
        roleDescription: nil,
        subrole: nil,
        title: nil,
        description: nil,
        help: nil,
        identifier: nil,
        value: nil,
        isEnabled: true,
        isValueSettable: false,
        secondaryActions: [],
        children: children
    )
}
