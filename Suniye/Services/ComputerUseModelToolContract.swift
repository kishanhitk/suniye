import Foundation

struct ComputerUseModelTool: Encodable, Sendable {
    struct Function: Encodable, Sendable {
        let name: String
        let description: String
        let parameters: Parameters
    }

    struct Parameters: Encodable, Sendable {
        struct RequiredVariant: Encodable, Sendable {
            let required: [String]
        }

        let type = "object"
        let properties: [String: Property]
        let required: [String]
        let oneOf: [RequiredVariant]?
        let additionalProperties = false
    }

    struct Property: Encodable, Sendable {
        let type: String
        let description: String
        let allowedValues: [String]?

        enum CodingKeys: String, CodingKey {
            case type
            case description
            case allowedValues = "enum"
        }
    }

    let type = "function"
    let operation: ComputerUseToolName
    let function: Function

    var name: ComputerUseToolName {
        operation
    }

    enum CodingKeys: String, CodingKey {
        case type
        case function
    }
}

enum ComputerUseModelToolCatalog {
    static let all: [ComputerUseModelTool] = [
        tool(.listApps, "List available macOS applications.", [:], []),
        tool(
            .getAppState,
            "Observe an application. This must be called once per assistant turn before " +
                "interacting with the app. The application is launched in the background " +
                "when needed.",
            [
                "app": string("Application display name, full path, or bundle identifier."),
                "disableDiff": boolean("Return a full Accessibility tree instead of a diff."),
            ],
            ["app"]
        ),
        tool(
            .click,
            "Click exactly one target: either an observed Accessibility element_index, or " +
                "window-relative screenshot x and y coordinates. Omit element_index when using " +
                "coordinates.",
            [
                "app": app,
                "element_index": integer(
                    "Element index from the latest observation. Use instead of x and y."
                ),
                "x": number(
                    "Window-relative horizontal screenshot coordinate. Requires y and no " +
                        "element_index."
                ),
                "y": number(
                    "Window-relative vertical screenshot coordinate. Requires x and no " +
                        "element_index."
                ),
                "mouse_button": string(
                    "Mouse button.",
                    values: ["left", "right", "middle", "l", "r", "m"]
                ),
                "click_count": integer("Number of clicks."),
            ],
            ["app"],
            alternatives: [["element_index"], ["x", "y"]]
        ),
        tool(
            .performSecondaryAction,
            "Perform an Accessibility action exposed by an observed element.",
            [
                "app": app,
                "element_index": integer("Element index from the latest observation."),
                "action": string("Exact action name exposed by the element."),
            ],
            ["app", "element_index", "action"]
        ),
        tool(
            .setValue,
            "Set the value of an editable Accessibility element.",
            [
                "app": app,
                "element_index": integer("Element index from the latest observation."),
                "value": string("Replacement value."),
            ],
            ["app", "element_index", "value"]
        ),
        tool(
            .selectText,
            "Select matching text or place the cursor around it in an editable element.",
            [
                "app": app,
                "element_index": integer("Element index from the latest observation."),
                "text": string("Exact text to match."),
                "prefix": string("Optional preceding text used to disambiguate the match."),
                "suffix": string("Optional following text used to disambiguate the match."),
                "selection_type": string(
                    "Selection behavior.",
                    values: ["text", "cursor_before", "cursor_after"]
                ),
            ],
            ["app", "element_index", "text"]
        ),
        tool(
            .scroll,
            "Scroll an observed Accessibility element.",
            [
                "app": app,
                "element_index": integer("Element index from the latest observation."),
                "direction": string(
                    "Scroll direction.",
                    values: ["up", "down", "left", "right", "u", "d", "l", "r"]
                ),
                "pages": number("Positive number of pages to scroll."),
            ],
            ["app", "element_index", "direction"]
        ),
        tool(
            .drag,
            "Drag between window-relative screenshot coordinates.",
            [
                "app": app,
                "from_x": number("Starting horizontal coordinate."),
                "from_y": number("Starting vertical coordinate."),
                "to_x": number("Ending horizontal coordinate."),
                "to_y": number("Ending vertical coordinate."),
            ],
            ["app", "from_x", "from_y", "to_x", "to_y"]
        ),
        tool(
            .pressKey,
            "Press an app-scoped key or key chord.",
            ["app": app, "key": string("Key or key chord in xdotool-style syntax.")],
            ["app", "key"]
        ),
        tool(
            .typeText,
            "Type text into the observed application.",
            ["app": app, "text": string("Exact text to type.")],
            ["app", "text"]
        ),
        tool(
            .setVoiceActivation,
            "Turn Suniye's always-listening Voice Activation on or off. Call with enabled=false when the user asks to stop listening (any phrasing, any language). This controls listening only; it does not end the current task or conversation.",
            ["enabled": boolean("false to stop listening for the wake phrase; true to resume.")],
            ["enabled"]
        ),
    ]

    private static let app = string(
        "Application display name, full path, or bundle identifier."
    )

    private static func tool(
        _ name: ComputerUseToolName,
        _ description: String,
        _ properties: [String: ComputerUseModelTool.Property],
        _ required: [String],
        alternatives: [[String]] = []
    ) -> ComputerUseModelTool {
        ComputerUseModelTool(
            operation: name,
            function: .init(
                name: name.rawValue,
                description: description,
                parameters: .init(
                    properties: properties,
                    required: required,
                    oneOf: alternatives.isEmpty
                        ? nil
                        : alternatives.map(ComputerUseModelTool.Parameters.RequiredVariant.init)
                )
            )
        )
    }

    private static func string(
        _ description: String,
        values: [String]? = nil
    ) -> ComputerUseModelTool.Property {
        .init(type: "string", description: description, allowedValues: values)
    }

    private static func integer(_ description: String) -> ComputerUseModelTool.Property {
        .init(type: "integer", description: description, allowedValues: nil)
    }

    private static func number(_ description: String) -> ComputerUseModelTool.Property {
        .init(type: "number", description: description, allowedValues: nil)
    }

    private static func boolean(_ description: String) -> ComputerUseModelTool.Property {
        .init(type: "boolean", description: description, allowedValues: nil)
    }
}
