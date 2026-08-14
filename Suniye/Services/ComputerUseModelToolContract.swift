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
    /// Code-mode advertises a single tool. The model writes JavaScript that
    /// drives `computer.*` (the ten UI actions plus set_voice_activation),
    /// awaiting each call; sequencing and error handling live in the script.
    static let all: [ComputerUseModelTool] = [
        tool(
            .nodeRepl,
            "Run JavaScript to control macOS apps. The runtime pre-injects `computer` (the " +
                "Computer Use API) and `nodeRepl.write(text)` for output; top-level await is " +
                "supported. Each call is independent — top-level variables do not persist between " +
                "calls, so re-observe with computer.get_app_state before acting. A call times out " +
                "after 30 seconds.",
            ["code": string("JavaScript source to execute.")],
            ["code"]
        ),
    ]

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
