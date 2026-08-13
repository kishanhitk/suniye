import Foundation

enum ComputerUseModelToolCallError: LocalizedError, Equatable, Sendable {
    case unknownTool(String)
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case let .unknownTool(name):
            return "Unknown Computer Use tool: \(name)."
        case let .invalidArguments(name):
            return "Invalid arguments for Computer Use tool: \(name)."
        }
    }
}

enum ComputerUseModelToolCallDecoder {
    static func decode(name: String, arguments: String) throws -> ComputerUseToolCall {
        guard let tool = ComputerUseToolName(rawValue: name) else {
            throw ComputerUseModelToolCallError.unknownTool(name)
        }

        let data = Data(arguments.utf8)
        do {
            return try decode(tool, from: data)
        } catch let error as ComputerUseModelToolCallError {
            throw error
        } catch {
            throw ComputerUseModelToolCallError.invalidArguments(name)
        }
    }

    private static func decode(
        _ tool: ComputerUseToolName,
        from data: Data
    ) throws -> ComputerUseToolCall {
        let decoder = JSONDecoder()
        switch tool {
        case .listApps:
            _ = try decoder.decode(EmptyArguments.self, from: data)
            return .listApps
        case .getAppState:
            let arguments = try decoder.decode(GetAppStateArguments.self, from: data)
            return .getAppState(
                app: arguments.app,
                disableDiff: arguments.disableDiff ?? false
            )
        case .click:
            return try decoder.decode(ClickArguments.self, from: data).toolCall
        case .performSecondaryAction:
            let arguments = try decoder.decode(SecondaryActionArguments.self, from: data)
            return .performSecondaryAction(
                app: arguments.app,
                elementIndex: arguments.elementIndex,
                action: arguments.action
            )
        case .setValue:
            let arguments = try decoder.decode(SetValueArguments.self, from: data)
            return .setValue(
                app: arguments.app,
                elementIndex: arguments.elementIndex,
                value: arguments.value
            )
        case .selectText:
            let arguments = try decoder.decode(SelectTextArguments.self, from: data)
            return .selectText(
                app: arguments.app,
                elementIndex: arguments.elementIndex,
                text: arguments.text,
                prefix: arguments.prefix,
                suffix: arguments.suffix,
                selectionType: arguments.selectionType ?? .text
            )
        case .scroll:
            let arguments = try decoder.decode(ScrollArguments.self, from: data)
            return .scroll(
                app: arguments.app,
                elementIndex: arguments.elementIndex,
                direction: arguments.direction,
                pages: arguments.pages ?? 1
            )
        case .drag:
            let arguments = try decoder.decode(DragArguments.self, from: data)
            return .drag(
                app: arguments.app,
                fromX: arguments.fromX,
                fromY: arguments.fromY,
                toX: arguments.toX,
                toY: arguments.toY
            )
        case .pressKey:
            let arguments = try decoder.decode(KeyArguments.self, from: data)
            return .pressKey(app: arguments.app, key: arguments.key)
        case .typeText:
            let arguments = try decoder.decode(TextArguments.self, from: data)
            return .typeText(app: arguments.app, text: arguments.text)
        case .setVoiceActivation:
            let arguments = try decoder.decode(SetVoiceActivationArguments.self, from: data)
            return .setVoiceActivation(enabled: arguments.enabled)
        }
    }
}

private struct SetVoiceActivationArguments: Decodable {
    let enabled: Bool
}

private struct EmptyArguments: Decodable {}

private struct GetAppStateArguments: Decodable {
    let app: String
    let disableDiff: Bool?
}

private struct ClickArguments: Decodable {
    let app: String
    let elementIndex: Int?
    let x: Double?
    let y: Double?
    let mouseButton: ComputerUseMouseButton?
    let clickCount: Int?

    enum CodingKeys: String, CodingKey {
        case app
        case elementIndex = "element_index"
        case x
        case y
        case mouseButton = "mouse_button"
        case clickCount = "click_count"
    }

    var toolCall: ComputerUseToolCall {
        get throws {
            let button = mouseButton ?? .left
            let count = clickCount ?? 1
            if let elementIndex {
                return .click(
                    ComputerUseClickRequest(
                        app: app,
                        elementIndex: elementIndex,
                        mouseButton: button,
                        clickCount: count
                    )
                )
            }
            guard let x, let y else {
                throw ComputerUseModelToolCallError.invalidArguments(
                    ComputerUseToolName.click.rawValue
                )
            }
            return .click(
                ComputerUseClickRequest(
                    app: app,
                    x: x,
                    y: y,
                    mouseButton: button,
                    clickCount: count
                )
            )
        }
    }
}

private struct SecondaryActionArguments: Decodable {
    let app: String
    let elementIndex: Int
    let action: String

    enum CodingKeys: String, CodingKey {
        case app
        case elementIndex = "element_index"
        case action
    }
}

private struct SetValueArguments: Decodable {
    let app: String
    let elementIndex: Int
    let value: String

    enum CodingKeys: String, CodingKey {
        case app
        case elementIndex = "element_index"
        case value
    }
}

private struct SelectTextArguments: Decodable {
    let app: String
    let elementIndex: Int
    let text: String
    let prefix: String?
    let suffix: String?
    let selectionType: ComputerUseTextSelectionType?

    enum CodingKeys: String, CodingKey {
        case app
        case elementIndex = "element_index"
        case text
        case prefix
        case suffix
        case selectionType = "selection_type"
    }
}

private struct ScrollArguments: Decodable {
    let app: String
    let elementIndex: Int
    let direction: ComputerUseScrollDirection
    let pages: Double?

    enum CodingKeys: String, CodingKey {
        case app
        case elementIndex = "element_index"
        case direction
        case pages
    }
}

private struct DragArguments: Decodable {
    let app: String
    let fromX: Double
    let fromY: Double
    let toX: Double
    let toY: Double

    enum CodingKeys: String, CodingKey {
        case app
        case fromX = "from_x"
        case fromY = "from_y"
        case toX = "to_x"
        case toY = "to_y"
    }
}

private struct KeyArguments: Decodable {
    let app: String
    let key: String
}

private struct TextArguments: Decodable {
    let app: String
    let text: String
}
