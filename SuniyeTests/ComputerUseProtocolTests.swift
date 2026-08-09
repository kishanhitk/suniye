import XCTest
@testable import Suniye

final class ComputerUseProtocolTests: XCTestCase {
    func testDesktopToolSurfaceMatchesTheRecoveredTenOperations() {
        XCTAssertEqual(
            ComputerUseToolName.allCases.map(\.rawValue),
            [
                "list_apps",
                "get_app_state",
                "click",
                "perform_secondary_action",
                "set_value",
                "select_text",
                "scroll",
                "drag",
                "press_key",
                "type_text",
            ]
        )
    }

    func testEveryToolCallMapsToItsPublicOperationName() {
        let calls: [ComputerUseToolCall] = [
            .listApps,
            .getAppState(app: "Calculator", disableDiff: false),
            .click(ComputerUseClickRequest(app: "Calculator", elementIndex: 1)),
            .performSecondaryAction(app: "Calculator", elementIndex: 1, action: "Show Menu"),
            .setValue(app: "Calculator", elementIndex: 1, value: "42"),
            .selectText(
                app: "Calculator",
                elementIndex: 1,
                text: "42",
                prefix: nil,
                suffix: nil,
                selectionType: .text
            ),
            .scroll(app: "Calculator", elementIndex: 1, direction: .down, pages: 1),
            .drag(app: "Calculator", fromX: 1, fromY: 2, toX: 3, toY: 4),
            .pressKey(app: "Calculator", key: "Return"),
            .typeText(app: "Calculator", text: "hello"),
        ]

        XCTAssertEqual(calls.map(\.name), ComputerUseToolName.allCases)
    }

    func testPublicMouseAndScrollAliasesDecodeToCanonicalValues() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(ComputerUseMouseButton.self, from: Data(#""m""#.utf8)),
            .middle
        )
        XCTAssertEqual(
            try decoder.decode(ComputerUseScrollDirection.self, from: Data(#""u""#.utf8)),
            .up
        )
        XCTAssertEqual(
            String(decoding: try JSONEncoder().encode(ComputerUseMouseButton.right), as: UTF8.self),
            #""right""#
        )
        XCTAssertEqual(
            String(decoding: try JSONEncoder().encode(ComputerUseScrollDirection.left), as: UTF8.self),
            #""left""#
        )
    }

    func testUnknownMouseAndScrollValuesFailDecoding() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(ComputerUseMouseButton.self, from: Data(#""side""#.utf8))
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(ComputerUseScrollDirection.self, from: Data(#""diagonal""#.utf8))
        )
    }

    func testSessionListsAppsWithoutSelectingOrLockingATarget() async throws {
        let calculator = ComputerUseApplication(
            id: "/System/Applications/Calculator.app",
            displayName: "Calculator",
            lastUsedDate: nil,
            useCount: 7,
            isRunning: true
        )
        let backend = RecordingComputerUseBackend(applications: [calculator])
        let session = ComputerUseSession(backend: backend)

        let result = try await session.execute(.listApps)

        XCTAssertEqual(result, .applications([calculator]))
        _ = try await session.execute(.pressKey(app: "Calculator", key: "Return"))
        let actionNames = await backend.actionNames
        XCTAssertEqual(actionNames, [.pressKey])
    }

    func testSessionDoesNotImposeAnExactAppIdentifierLock() async throws {
        let backend = RecordingComputerUseBackend()
        let session = ComputerUseSession(backend: backend)

        let state = try await session.execute(
            .getAppState(app: "Calculator", disableDiff: false)
        )
        XCTAssertEqual(
            state,
            .appState(
                ComputerUseAppState(
                    app: "Calculator",
                    screenshot: URL(fileURLWithPath: "/tmp/calculator.jpg"),
                    text: "0 AXWindow: Calculator"
                )
            )
        )

        _ = try await session.execute(
            .click(ComputerUseClickRequest(app: "com.apple.calculator", elementIndex: 4))
        )
        _ = try await session.execute(.pressKey(app: "Calculator", key: "Return"))

        let actionNames = await backend.actionNames
        XCTAssertEqual(actionNames, [.click, .pressKey])
    }

    func testEveryActionRoutesThroughTheTypedBackendBoundary() async throws {
        let backend = RecordingComputerUseBackend()
        let session = ComputerUseSession(backend: backend)
        _ = try await session.execute(.getAppState(app: "Calculator", disableDiff: true))

        let actions: [ComputerUseToolCall] = [
            .click(
                ComputerUseClickRequest(
                    app: "Calculator",
                    x: 10,
                    y: 20,
                    mouseButton: .right,
                    clickCount: 2
                )
            ),
            .performSecondaryAction(app: "Calculator", elementIndex: 1, action: "Show Menu"),
            .setValue(app: "Calculator", elementIndex: 2, value: "42"),
            .selectText(
                app: "Calculator",
                elementIndex: 3,
                text: "42",
                prefix: "Result",
                suffix: nil,
                selectionType: .text
            ),
            .scroll(app: "Calculator", elementIndex: 4, direction: .down, pages: 1),
            .drag(app: "Calculator", fromX: 1, fromY: 2, toX: 3, toY: 4),
            .pressKey(app: "Calculator", key: "Super_L+a"),
            .typeText(app: "Calculator", text: "hello"),
        ]

        for action in actions {
            let result = try await session.execute(action)
            XCTAssertEqual(result, .actionCompleted)
        }

        let actionNames = await backend.actionNames
        let lastClick = await backend.lastClick
        let lastSelectionType = await backend.lastSelectionType
        let lastDisableDiff = await backend.lastDisableDiff
        XCTAssertEqual(
            actionNames,
            [
                .click,
                .performSecondaryAction,
                .setValue,
                .selectText,
                .scroll,
                .drag,
                .pressKey,
                .typeText,
            ]
        )
        XCTAssertEqual(lastClick?.mouseButton, .right)
        XCTAssertEqual(lastSelectionType, .text)
        XCTAssertEqual(lastDisableDiff, true)
    }

}

private actor RecordingComputerUseBackend: ComputerUseToolServing {
    private(set) var actionNames: [ComputerUseToolName] = []
    private(set) var lastClick: ComputerUseClickRequest?
    private(set) var lastSelectionType: ComputerUseTextSelectionType?
    private(set) var lastDisableDiff: Bool?

    private let applications: [ComputerUseApplication]

    init(applications: [ComputerUseApplication] = []) {
        self.applications = applications
    }

    func listApps() async throws -> [ComputerUseApplication] {
        applications
    }

    func getAppState(app: String, disableDiff: Bool) async throws -> ComputerUseAppState {
        lastDisableDiff = disableDiff
        return ComputerUseAppState(
            app: app,
            screenshot: URL(fileURLWithPath: "/tmp/\(app.lowercased()).jpg"),
            text: "0 AXWindow: \(app)"
        )
    }

    func click(_ request: ComputerUseClickRequest) async throws {
        lastClick = request
        actionNames.append(.click)
    }

    func performSecondaryAction(app: String, elementIndex: Int, action: String) async throws {
        actionNames.append(.performSecondaryAction)
    }

    func setValue(app: String, elementIndex: Int, value: String) async throws {
        actionNames.append(.setValue)
    }

    func selectText(
        app: String,
        elementIndex: Int,
        text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType
    ) async throws {
        lastSelectionType = selectionType
        actionNames.append(.selectText)
    }

    func scroll(
        app: String,
        elementIndex: Int,
        direction: ComputerUseScrollDirection,
        pages: Double
    ) async throws {
        actionNames.append(.scroll)
    }

    func drag(
        app: String,
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double
    ) async throws {
        actionNames.append(.drag)
    }

    func pressKey(app: String, key: String) async throws {
        actionNames.append(.pressKey)
    }

    func typeText(app: String, text: String) async throws {
        actionNames.append(.typeText)
    }
}
