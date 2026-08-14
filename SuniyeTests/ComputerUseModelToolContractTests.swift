import XCTest
@testable import Suniye

final class ComputerUseModelToolContractTests: XCTestCase {
    func testModelReceivesOnlyTheCodeModeTool() {
        XCTAssertEqual(ComputerUseModelToolCatalog.all.map(\.name), [.nodeRepl])
    }

    func testNodeReplToolTakesASingleRequiredCodeArgument() throws {
        let tool = try XCTUnwrap(ComputerUseModelToolCatalog.all.first { $0.name == .nodeRepl })

        XCTAssertEqual(Set(tool.function.parameters.properties.keys), ["code"])
        XCTAssertEqual(tool.function.parameters.required, ["code"])
        XCTAssertTrue(tool.function.description.contains("computer"))
        XCTAssertTrue(tool.function.description.contains("await"))
    }

    func testNodeReplSchemaEncodesToSingleCodeStringField() throws {
        let encoded = try JSONEncoder().encode(ComputerUseModelToolCatalog.all)
        let tools = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]
        )
        XCTAssertEqual(tools.count, 1)
        let function = try XCTUnwrap(tools[0]["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "node_repl")
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["code"])
        let code = try XCTUnwrap(properties["code"] as? [String: Any])
        XCTAssertEqual(code["type"] as? String, "string")
        XCTAssertEqual(parameters["required"] as? [String], ["code"])
    }

    // UX plan: the spoken off-switch goes through the model, so the tool
    // decodes for any phrasing the model maps onto it.
    func testSetVoiceActivationDecodes() throws {
        XCTAssertEqual(
            try ComputerUseModelToolCallDecoder.decode(
                name: "set_voice_activation",
                arguments: #"{"enabled": false}"#
            ),
            .setVoiceActivation(enabled: false)
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
