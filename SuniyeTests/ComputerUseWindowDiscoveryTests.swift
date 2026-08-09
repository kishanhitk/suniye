import CoreGraphics
import XCTest
@testable import Suniye

final class ComputerUseWindowDiscoveryTests: XCTestCase {
    func testOrderedWindowsCrossReferencesCGAndAXCandidatesInCGOrder() async throws {
        let inventory = StubComputerUseWindowInventory(
            cgWindows: [
                cgWindow(id: 30, title: "Front document", x: 10, width: 600),
                cgWindow(id: 20, title: "Other app", x: 20, width: 700, pid: 999),
                cgWindow(id: 10, title: "Back document", x: 30, width: 900),
                cgWindow(id: 5, title: "Overlay", x: 40, width: 1_000, layer: 3),
            ],
            axWindows: [
                axWindow(ordinal: 0, title: "Back document", x: 30, width: 900),
                axWindow(ordinal: 1, title: "Front document", x: 10, width: 600),
            ]
        )
        let discovery = ComputerUseWindowDiscovery(inventory: inventory)

        let windows = try await discovery.orderedWindows(processIdentifier: 123)

        XCTAssertEqual(windows.map(\.id), [30, 10])
        XCTAssertEqual(windows.map(\.accessibilityOrdinal), [1, 0])
    }

    func testWindowOrderingDoesNotAddTitleAreaOrFocusedHeuristics() async throws {
        let inventory = StubComputerUseWindowInventory(
            cgWindows: [
                cgWindow(id: 1, title: nil, x: 10, width: 300),
                cgWindow(id: 2, title: "Larger focused window", x: 20, width: 1_200),
            ],
            axWindows: [
                axWindow(ordinal: 0, title: nil, x: 10, width: 300),
                axWindow(
                    ordinal: 1,
                    title: "Larger focused window",
                    x: 20,
                    width: 1_200,
                    isFocused: true,
                    isMain: true
                ),
            ]
        )
        let discovery = ComputerUseWindowDiscovery(inventory: inventory)

        let windows = try await discovery.orderedWindows(processIdentifier: 123)

        XCTAssertEqual(windows.map(\.id), [1, 2])
    }

    func testMatchingBoundsTakePrecedenceOverDifferentDynamicTitles() async throws {
        let inventory = StubComputerUseWindowInventory(
            cgWindows: [
                cgWindow(id: 1, title: "Battery", x: 10, width: 300),
            ],
            axWindows: [
                axWindow(
                    ordinal: 0,
                    title: "Battery – Charged to 80% Limit",
                    x: 10,
                    width: 300
                ),
            ]
        )
        let discovery = ComputerUseWindowDiscovery(inventory: inventory)

        let windows = try await discovery.orderedWindows(processIdentifier: 123)

        XCTAssertEqual(windows.map(\.id), [1])
        XCTAssertEqual(windows.first?.accessibilityOrdinal, 0)
    }

    func testEmptyCGWindowsAreExcluded() async throws {
        let inventory = StubComputerUseWindowInventory(
            cgWindows: [cgWindow(id: 2, title: "Empty", x: 20, width: 0)],
            axWindows: [axWindow(ordinal: 0, title: "Empty", x: 20, width: 0)]
        )
        let discovery = ComputerUseWindowDiscovery(inventory: inventory)

        let windows = try await discovery.orderedWindows(processIdentifier: 123)

        XCTAssertTrue(windows.isEmpty)
    }

    func testTitleCanCrossReferenceAWindowWhenAXBoundsAreUnavailable() async throws {
        let inventory = StubComputerUseWindowInventory(
            cgWindows: [cgWindow(id: 7, title: "Document", x: 10, width: 300)],
            axWindows: [
                ComputerUseAXWindowSnapshot(
                    ordinal: 4,
                    title: "Document",
                    bounds: nil,
                    isFocused: false,
                    isMain: false
                ),
            ]
        )
        let discovery = ComputerUseWindowDiscovery(inventory: inventory)

        let windows = try await discovery.orderedWindows(processIdentifier: 123)

        XCTAssertEqual(windows.map(\.id), [7])
        XCTAssertEqual(windows.first?.accessibilityOrdinal, 4)
    }

    func testPrimaryWindowWaitPollsUntilAWindowAppears() async throws {
        let expected = ComputerUseWindow(
            id: 7,
            ownerProcessIdentifier: 123,
            title: "Calculator",
            bounds: CGRect(x: 10, y: 10, width: 300, height: 500),
            layer: 0,
            isOnScreen: true,
            accessibilityOrdinal: 0,
            isFocused: false,
            isMain: true
        )
        let discovery = SequencedComputerUseWindowDiscovery(responses: [[], [expected]])

        let window = try await discovery.waitUntilHasPrimaryWindow(
            processIdentifier: 123,
            timeout: .seconds(1),
            pollingInterval: .milliseconds(1)
        )

        XCTAssertEqual(window, expected)
        let callCount = await discovery.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testPrimaryWindowWaitReturnsNilAtItsDeadline() async throws {
        let discovery = SequencedComputerUseWindowDiscovery(responses: [[]])

        let window = try await discovery.waitUntilHasPrimaryWindow(
            processIdentifier: 123,
            timeout: .zero,
            pollingInterval: .milliseconds(1)
        )

        XCTAssertNil(window)
        let callCount = await discovery.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testWindowDescriptionDecoderCreatesTypedSnapshot() {
        let snapshot = ComputerUseWindowDescriptionDecoder.decode([
            kCGWindowNumber as String: NSNumber(value: 7),
            kCGWindowOwnerPID as String: NSNumber(value: 123),
            kCGWindowName as String: "Document",
            kCGWindowBounds as String: [
                "X": NSNumber(value: 10),
                "Y": NSNumber(value: 20),
                "Width": NSNumber(value: 300),
                "Height": NSNumber(value: 400),
            ],
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowIsOnscreen as String: NSNumber(value: true),
        ])

        XCTAssertEqual(
            snapshot,
            ComputerUseCGWindowSnapshot(
                id: 7,
                ownerProcessIdentifier: 123,
                title: "Document",
                bounds: CGRect(x: 10, y: 20, width: 300, height: 400),
                layer: 0,
                isOnScreen: true
            )
        )
    }

    func testWindowDescriptionDecoderRejectsMissingIdentity() {
        let snapshot = ComputerUseWindowDescriptionDecoder.decode([
            kCGWindowBounds as String: [
                "X": NSNumber(value: 10),
                "Y": NSNumber(value: 20),
                "Width": NSNumber(value: 300),
                "Height": NSNumber(value: 400),
            ],
            kCGWindowLayer as String: NSNumber(value: 0),
        ])

        XCTAssertNil(snapshot)
    }

    private func cgWindow(
        id: UInt32,
        title: String?,
        x: CGFloat,
        width: CGFloat,
        pid: Int32 = 123,
        layer: Int = 0
    ) -> ComputerUseCGWindowSnapshot {
        ComputerUseCGWindowSnapshot(
            id: id,
            ownerProcessIdentifier: pid,
            title: title,
            bounds: CGRect(x: x, y: 10, width: width, height: 500),
            layer: layer,
            isOnScreen: true
        )
    }

    private func axWindow(
        ordinal: Int,
        title: String?,
        x: CGFloat,
        width: CGFloat,
        isFocused: Bool = false,
        isMain: Bool = false
    ) -> ComputerUseAXWindowSnapshot {
        ComputerUseAXWindowSnapshot(
            ordinal: ordinal,
            title: title,
            bounds: CGRect(x: x, y: 10, width: width, height: 500),
            isFocused: isFocused,
            isMain: isMain
        )
    }
}

private actor SequencedComputerUseWindowDiscovery: ComputerUseWindowDiscovering {
    private var responses: [[ComputerUseWindow]]
    private(set) var callCount = 0

    init(responses: [[ComputerUseWindow]]) {
        self.responses = responses
    }

    func orderedWindows(processIdentifier: Int32) -> [ComputerUseWindow] {
        callCount += 1
        guard responses.count > 1 else {
            return responses.first ?? []
        }
        return responses.removeFirst()
    }
}

private struct StubComputerUseWindowInventory: ComputerUseWindowInventoryProviding {
    let cgWindows: [ComputerUseCGWindowSnapshot]
    let axWindows: [ComputerUseAXWindowSnapshot]

    func onScreenWindows() throws -> [ComputerUseCGWindowSnapshot] {
        cgWindows
    }

    func accessibilityWindows(processIdentifier: Int32) throws
        -> [ComputerUseAXWindowSnapshot]
    {
        axWindows
    }
}
