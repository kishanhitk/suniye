import Foundation

struct ComputerUseChatCompletionTool: Encodable {
    struct Function: Encodable {
        let name: String
        let description: String
        let parameters: Parameters
    }

    struct Parameters: Encodable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
        let additionalProperties = false
    }

    struct Property: Encodable {
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
    let function: Function
}

enum ComputerUseModelTools {
    static let all: [ComputerUseChatCompletionTool] = [
        tool(
            name: "select_target",
            description: "Select the macOS application to observe. This does not perform input.",
            properties: [
                "app": string("An exact application display name or bundle identifier."),
            ],
            required: ["app"]
        ),
        tool(
            name: "click_coordinates",
            description: "Click window-relative screenshot coordinates in the observed application.",
            properties: [
                "x": number("Horizontal coordinate relative to the observed window."),
                "y": number("Vertical coordinate relative to the observed window."),
                "click_count": integer("Number of clicks. Use 1 unless multiple clicks are needed."),
                "mouse_button": string("Mouse button.", allowedValues: ["left", "right", "middle"]),
            ],
            required: ["x", "y"]
        ),
        tool(
            name: "click_element",
            description: "Click an element index from the current Accessibility observation.",
            properties: [
                "element_index": integer("Element index from the current Accessibility text."),
                "click_count": integer("Number of clicks. Use 1 unless multiple clicks are needed."),
                "mouse_button": string("Mouse button.", allowedValues: ["left", "right", "middle"]),
            ],
            required: ["element_index"]
        ),
        tool(
            name: "press_key",
            description: "Press one key or key chord in the observed application.",
            properties: [
                "key": string("A key such as Return, Tab, a, or Control_L+a."),
            ],
            required: ["key"]
        ),
        tool(
            name: "scroll",
            description: "Scroll an indexed Accessibility element in the observed application.",
            properties: [
                "element_index": integer("Element index from the current Accessibility text."),
                "direction": string("Scroll direction.", allowedValues: ["up", "down", "left", "right"]),
                "pages": number("Positive number of pages to scroll."),
            ],
            required: ["element_index", "direction"]
        ),
        tool(
            name: "type_text",
            description: "Type task-required text into the focused control in the observed application.",
            properties: [
                "text": string("The exact text required by the user's task."),
            ],
            required: ["text"]
        ),
        tool(
            name: "set_value",
            description: "Replace the value of an editable Accessibility element.",
            properties: [
                "element_index": integer("Editable element index from the current Accessibility text."),
                "value": string("The exact replacement value required by the user's task."),
            ],
            required: ["element_index", "value"]
        ),
        tool(
            name: "drag",
            description: "Drag between two window-relative screenshot coordinates.",
            properties: [
                "from_x": number("Starting horizontal coordinate."),
                "from_y": number("Starting vertical coordinate."),
                "to_x": number("Ending horizontal coordinate."),
                "to_y": number("Ending vertical coordinate."),
            ],
            required: ["from_x", "from_y", "to_x", "to_y"]
        ),
        tool(
            name: "select_text",
            description: "Select matching text or place the cursor around it in an editable Accessibility element.",
            properties: [
                "element_index": integer("Editable element index from the current Accessibility text."),
                "text": string("Exact text to match."),
                "selection_type": string("Selection behavior.", allowedValues: ["text", "cursor_before", "cursor_after"]),
                "prefix": string("Optional preceding text used to disambiguate a match."),
                "suffix": string("Optional following text used to disambiguate a match."),
            ],
            required: ["element_index", "text", "selection_type"]
        ),
        tool(
            name: "perform_secondary_action",
            description: "Perform an Accessibility action explicitly exposed by the current element.",
            properties: [
                "element_index": integer("Element index from the current Accessibility text."),
                "action": string("Exact exposed Accessibility action name."),
            ],
            required: ["element_index", "action"]
        ),
        tool(
            name: "completed",
            description: "Finish because the user's task is complete.",
            properties: ["message": string("Concise result for the user.")],
            required: ["message"]
        ),
        tool(
            name: "ask_user",
            description: "Pause because the user must provide a decision or missing information.",
            properties: ["question": string("Specific question for the user.")],
            required: ["question"]
        ),
        tool(
            name: "blocked",
            description: "Stop because the task cannot continue safely or with the available controls.",
            properties: ["reason": string("Specific reason the task is blocked.")],
            required: ["reason"]
        ),
        tool(
            name: "retryable_failure",
            description: "Request another observation only when fresh state may resolve an insufficient observation.",
            properties: ["reason": string("Why another observation may help.")],
            required: ["reason"]
        ),
    ]

    private static func tool(
        name: String,
        description: String,
        properties: [String: ComputerUseChatCompletionTool.Property],
        required: [String]
    ) -> ComputerUseChatCompletionTool {
        ComputerUseChatCompletionTool(
            function: .init(
                name: name,
                description: description,
                parameters: .init(properties: properties, required: required)
            )
        )
    }

    private static func string(
        _ description: String,
        allowedValues: [String]? = nil
    ) -> ComputerUseChatCompletionTool.Property {
        .init(type: "string", description: description, allowedValues: allowedValues)
    }

    private static func integer(_ description: String) -> ComputerUseChatCompletionTool.Property {
        .init(type: "integer", description: description, allowedValues: nil)
    }

    private static func number(_ description: String) -> ComputerUseChatCompletionTool.Property {
        .init(type: "number", description: description, allowedValues: nil)
    }
}

enum ComputerUseModelToolCallParser {
    static func parse(name: String, arguments: String) throws -> ComputerUseModelDecision {
        let argumentsData = Data(arguments.utf8)
        let rawArguments: Any
        do {
            rawArguments = try JSONSerialization.jsonObject(with: argumentsData)
        } catch {
            throw ComputerUseModelError.invalidResponse("the tool arguments were not valid JSON")
        }
        guard let object = rawArguments as? [String: Any] else {
            throw ComputerUseModelError.invalidResponse("the tool arguments were not an object")
        }

        let decision: [String: Any]
        switch name {
        case "select_target":
            decision = ["kind": "target", "app": object["app"] as Any]
        case "click_coordinates", "click_element":
            decision = actionDecision(kind: "click", arguments: object)
        case "press_key":
            decision = actionDecision(kind: "press_key", arguments: object)
        case "scroll":
            decision = actionDecision(kind: "scroll", arguments: object)
        case "type_text":
            decision = actionDecision(kind: "type_text", arguments: object)
        case "set_value":
            decision = actionDecision(kind: "set_value", arguments: object)
        case "drag":
            decision = actionDecision(kind: "drag", arguments: object)
        case "select_text":
            decision = actionDecision(kind: "select_text", arguments: object)
        case "perform_secondary_action":
            decision = actionDecision(kind: "perform_secondary_action", arguments: object)
        case "completed":
            decision = ["kind": "completed", "message": object["message"] as Any]
        case "ask_user":
            decision = ["kind": "ask_user", "question": object["question"] as Any]
        case "blocked":
            decision = ["kind": "blocked", "reason": object["reason"] as Any]
        case "retryable_failure":
            decision = ["kind": "retryable_failure", "reason": object["reason"] as Any]
        default:
            throw ComputerUseModelError.invalidResponse("the response used an unknown tool")
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: decision)
            return try ComputerUseModelDecisionParser.parse(String(decoding: data, as: UTF8.self))
        } catch let error as ComputerUseModelError {
            throw error
        } catch {
            throw ComputerUseModelError.invalidResponse("the tool arguments did not match the action schema")
        }
    }

    private static func actionDecision(
        kind: String,
        arguments: [String: Any]
    ) -> [String: Any] {
        var action = arguments
        action["kind"] = kind
        return ["kind": "action", "action": action]
    }
}
