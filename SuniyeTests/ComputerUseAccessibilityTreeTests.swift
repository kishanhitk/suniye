import XCTest
@testable import Suniye

final class ComputerUseAccessibilityTreeTests: XCTestCase {
    func testFullRevisionRendersDepthFirstWithSequentialElementIDs() async {
        let store = ComputerUseAccessibilityRevisionStore()
        let snapshot = ComputerUseAXSnapshot(roots: [
            node(
                role: "AXWindow",
                title: "Calculator",
                actions: ["AXRaise"],
                children: [
                    node(
                        role: "AXButton",
                        title: "Equals",
                        description: "Calculate result",
                        help: "Performs the calculation",
                        identifier: "equals",
                        enabled: false,
                        actions: ["AXPress", "AXShowMenu"]
                    ),
                ]
            ),
        ])

        let revision = await store.revision(
            targetKey: "com.apple.calculator",
            snapshot: snapshot,
            disableDiff: false
        )

        XCTAssertEqual(
            revision.text,
            """
            0: AXWindow "Calculator" Secondary Actions: AXRaise
              1: AXButton "Equals" Description: "Calculate result" Help: "Performs the calculation" ID: "equals" (disabled) Secondary Actions: AXPress, AXShowMenu
            """
        )
        XCTAssertEqual(revision.elements[0]?.path, [])
        XCTAssertEqual(revision.elements[1]?.path, [0])
    }

    func testSecureValuesAreRedactedWhileOrdinaryValuesRender() async {
        let store = ComputerUseAccessibilityRevisionStore()
        let snapshot = ComputerUseAXSnapshot(roots: [
            node(role: "AXTextField", value: "Kishan", valueSettable: true),
            node(role: "AXSecureTextField", value: "secret", valueSettable: true),
        ])

        let revision = await store.revision(
            targetKey: "example",
            snapshot: snapshot,
            disableDiff: false
        )

        XCTAssertTrue(revision.text.contains("Value: \"Kishan\" (value settable)"))
        XCTAssertTrue(revision.text.contains("Value: [redacted] (value settable)"))
        XCTAssertFalse(revision.text.contains("secret"))
    }

    func testChangedRevisionInheritsStableIDAndReturnsDiff() async {
        let store = ComputerUseAccessibilityRevisionStore()
        let first = ComputerUseAXSnapshot(roots: [
            node(role: "AXStaticText", identifier: "result", value: "41"),
        ])
        let second = ComputerUseAXSnapshot(roots: [
            node(role: "AXStaticText", identifier: "result", value: "42"),
        ])

        let original = await store.revision(
            targetKey: "calculator",
            snapshot: first,
            disableDiff: false
        )
        let changed = await store.revision(
            targetKey: "calculator",
            snapshot: second,
            disableDiff: false
        )

        XCTAssertEqual(original.elements.keys.sorted(), [0])
        XCTAssertEqual(changed.elements.keys.sorted(), [0])
        XCTAssertEqual(
            changed.text,
            """
            - 0: AXStaticText ID: "result" Value: "41"
            + 0: AXStaticText ID: "result" Value: "42"
            """
        )
    }

    func testUnchangedRevisionReturnsFullTreeInsteadOfEmptyDiff() async {
        let store = ComputerUseAccessibilityRevisionStore()
        let snapshot = ComputerUseAXSnapshot(roots: [node(role: "AXButton", title: "OK")])

        _ = await store.revision(targetKey: "example", snapshot: snapshot, disableDiff: false)
        let unchanged = await store.revision(
            targetKey: "example",
            snapshot: snapshot,
            disableDiff: false
        )

        XCTAssertEqual(unchanged.text, "0: AXButton \"OK\"")
    }

    func testDisableDiffReturnsFullCurrentTree() async {
        let store = ComputerUseAccessibilityRevisionStore()
        _ = await store.revision(
            targetKey: "example",
            snapshot: ComputerUseAXSnapshot(roots: [node(role: "AXButton", title: "Before")]),
            disableDiff: false
        )

        let revision = await store.revision(
            targetKey: "example",
            snapshot: ComputerUseAXSnapshot(roots: [node(role: "AXButton", title: "After")]),
            disableDiff: true
        )

        XCTAssertEqual(revision.text, "0: AXButton \"After\"")
    }

    func testInsertedElementGetsNewIDAndRemovedElementLeavesCurrentMap() async {
        let store = ComputerUseAccessibilityRevisionStore()
        _ = await store.revision(
            targetKey: "example",
            snapshot: ComputerUseAXSnapshot(roots: [
                node(role: "AXButton", title: "Keep", identifier: "keep"),
                node(role: "AXButton", title: "Remove", identifier: "remove"),
            ]),
            disableDiff: false
        )

        let revision = await store.revision(
            targetKey: "example",
            snapshot: ComputerUseAXSnapshot(roots: [
                node(role: "AXButton", title: "Keep", identifier: "keep"),
                node(role: "AXButton", title: "Add", identifier: "add"),
            ]),
            disableDiff: false
        )

        XCTAssertEqual(revision.elements.keys.sorted(), [0, 2])
        XCTAssertTrue(revision.text.contains("- 1: AXButton \"Remove\" ID: \"remove\""))
        XCTAssertTrue(revision.text.contains("+ 2: AXButton \"Add\" ID: \"add\""))
    }

    private func node(
        role: String,
        title: String? = nil,
        description: String? = nil,
        help: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        enabled: Bool = true,
        valueSettable: Bool = false,
        actions: [String] = [],
        children: [ComputerUseAXNode] = []
    ) -> ComputerUseAXNode {
        ComputerUseAXNode(
            role: role,
            roleDescription: nil,
            subrole: nil,
            title: title,
            description: description,
            help: help,
            identifier: identifier,
            value: value,
            isEnabled: enabled,
            isValueSettable: valueSettable,
            secondaryActions: actions,
            children: children
        )
    }
}
