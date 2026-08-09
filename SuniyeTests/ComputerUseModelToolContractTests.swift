import XCTest
@testable import Suniye

final class ComputerUseModelToolContractTests: XCTestCase {
    func testModelReceivesExactlyTheDesktopToolSurface() {
        XCTAssertEqual(
            ComputerUseModelToolCatalog.all.map(\.name),
            ComputerUseToolName.allCases
        )
    }

    func testClickToolExplainsTheElementOrCoordinateChoice() throws {
        let click = try XCTUnwrap(
            ComputerUseModelToolCatalog.all.first { $0.name == .click }
        )

        XCTAssertTrue(click.function.description.contains("Omit element_index"))
        XCTAssertTrue(
            try XCTUnwrap(click.function.parameters.properties["x"])
                .description.contains("no element_index")
        )
        XCTAssertTrue(
            try XCTUnwrap(click.function.parameters.properties["y"])
                .description.contains("no element_index")
        )
        XCTAssertEqual(
            click.function.parameters.oneOf?.map(\.required),
            [["element_index"], ["x", "y"]]
        )
    }

    func testToolSchemasPreserveRecoveredArgumentsAndRequiredFields() throws {
        let encoded = try JSONEncoder().encode(ComputerUseModelToolCatalog.all)
        let tools = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]
        )
        let contracts = Dictionary(uniqueKeysWithValues: try tools.map { tool in
            let function = try XCTUnwrap(tool["function"] as? [String: Any])
            let name = try XCTUnwrap(function["name"] as? String)
            let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
            let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
            let required = try XCTUnwrap(parameters["required"] as? [String])
            return (name, ToolContract(properties: Set(properties.keys), required: Set(required)))
        })

        XCTAssertEqual(
            contracts,
            [
                "list_apps": ToolContract(properties: [], required: []),
                "get_app_state": ToolContract(
                    properties: ["app", "disableDiff"],
                    required: ["app"]
                ),
                "click": ToolContract(
                    properties: ["app", "element_index", "x", "y", "mouse_button", "click_count"],
                    required: ["app"]
                ),
                "perform_secondary_action": ToolContract(
                    properties: ["app", "element_index", "action"],
                    required: ["app", "element_index", "action"]
                ),
                "set_value": ToolContract(
                    properties: ["app", "element_index", "value"],
                    required: ["app", "element_index", "value"]
                ),
                "select_text": ToolContract(
                    properties: ["app", "element_index", "text", "prefix", "suffix", "selection_type"],
                    required: ["app", "element_index", "text"]
                ),
                "scroll": ToolContract(
                    properties: ["app", "element_index", "direction", "pages"],
                    required: ["app", "element_index", "direction"]
                ),
                "drag": ToolContract(
                    properties: ["app", "from_x", "from_y", "to_x", "to_y"],
                    required: ["app", "from_x", "from_y", "to_x", "to_y"]
                ),
                "press_key": ToolContract(
                    properties: ["app", "key"],
                    required: ["app", "key"]
                ),
                "type_text": ToolContract(
                    properties: ["app", "text"],
                    required: ["app", "text"]
                ),
            ]
        )
    }

    func testToolCallsDecodeToTheTypedDesktopContractWithPublicDefaults() throws {
        let calls: [(String, String, ComputerUseToolCall)] = [
            ("list_apps", "{}", .listApps),
            (
                "get_app_state",
                #"{"app":"Calculator"}"#,
                .getAppState(app: "Calculator", disableDiff: false)
            ),
            (
                "click",
                #"{"app":"Calculator","element_index":7}"#,
                .click(ComputerUseClickRequest(app: "Calculator", elementIndex: 7))
            ),
            (
                "perform_secondary_action",
                #"{"app":"Calculator","element_index":2,"action":"Show Menu"}"#,
                .performSecondaryAction(app: "Calculator", elementIndex: 2, action: "Show Menu")
            ),
            (
                "set_value",
                #"{"app":"Calculator","element_index":3,"value":"42"}"#,
                .setValue(app: "Calculator", elementIndex: 3, value: "42")
            ),
            (
                "select_text",
                #"{"app":"Notes","element_index":4,"text":"hello"}"#,
                .selectText(
                    app: "Notes",
                    elementIndex: 4,
                    text: "hello",
                    prefix: nil,
                    suffix: nil,
                    selectionType: .text
                )
            ),
            (
                "scroll",
                #"{"app":"Notes","element_index":5,"direction":"d"}"#,
                .scroll(app: "Notes", elementIndex: 5, direction: .down, pages: 1)
            ),
            (
                "drag",
                #"{"app":"Preview","from_x":1,"from_y":2,"to_x":3,"to_y":4}"#,
                .drag(app: "Preview", fromX: 1, fromY: 2, toX: 3, toY: 4)
            ),
            (
                "press_key",
                #"{"app":"Notes","key":"super+a"}"#,
                .pressKey(app: "Notes", key: "super+a")
            ),
            (
                "type_text",
                #"{"app":"Notes","text":"hello"}"#,
                .typeText(app: "Notes", text: "hello")
            ),
        ]

        for (name, arguments, expected) in calls {
            XCTAssertEqual(
                try ComputerUseModelToolCallDecoder.decode(
                    name: name,
                    arguments: arguments
                ),
                expected,
                name
            )
        }
    }
}

private struct ToolContract: Equatable {
    let properties: Set<String>
    let required: Set<String>
}
