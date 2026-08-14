import Foundation

enum ComputerUseToolName: String, CaseIterable, Codable, Equatable, Sendable {
    case listApps = "list_apps"
    case getAppState = "get_app_state"
    case click
    case performSecondaryAction = "perform_secondary_action"
    case setValue = "set_value"
    case selectText = "select_text"
    case scroll
    case drag
    case pressKey = "press_key"
    case typeText = "type_text"
    case setVoiceActivation = "set_voice_activation"
    case nodeRepl = "node_repl"
}

struct ComputerUseApplication: Codable, Equatable, Sendable {
    let id: String
    let displayName: String?
    let lastUsedDate: Date?
    let useCount: Int?
    let isRunning: Bool?
    /// The app the user is currently looking at. Present (true) only for the
    /// frontmost app so compact encodings stay small.
    let isFrontmost: Bool?

    init(
        id: String,
        displayName: String?,
        lastUsedDate: Date?,
        useCount: Int?,
        isRunning: Bool?,
        isFrontmost: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.lastUsedDate = lastUsedDate
        self.useCount = useCount
        self.isRunning = isRunning
        self.isFrontmost = isFrontmost
    }
}

struct ComputerUseAppState: Codable, Equatable, Sendable {
    let app: String
    let screenshot: URL?
    let text: String

    enum CodingKeys: String, CodingKey {
        case app
        case screenshot
        case text
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        if let screenshot {
            try container.encode(screenshot, forKey: .screenshot)
        } else {
            try container.encodeNil(forKey: .screenshot)
        }
        try container.encode(text, forKey: .text)
    }
}

enum ComputerUseMouseButton: String, Codable, Equatable, Sendable {
    case left
    case right
    case middle

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self).lowercased()
        switch value {
        case "left", "l": self = .left
        case "right", "r": self = .right
        case "middle", "m": self = .middle
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported mouse button: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ComputerUseScrollDirection: String, Codable, Equatable, Sendable {
    case up
    case down
    case left
    case right

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self).lowercased()
        switch value {
        case "up", "u": self = .up
        case "down", "d": self = .down
        case "left", "l": self = .left
        case "right", "r": self = .right
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported scroll direction: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ComputerUseTextSelectionType: String, Codable, Equatable, Sendable {
    case text
    case cursorBefore = "cursor_before"
    case cursorAfter = "cursor_after"
}

struct ComputerUseClickRequest: Codable, Equatable, Sendable {
    let app: String
    let target: ComputerUseClickTarget
    let mouseButton: ComputerUseMouseButton
    let clickCount: Int

    init(
        app: String,
        elementIndex: Int,
        mouseButton: ComputerUseMouseButton = .left,
        clickCount: Int = 1
    ) {
        self.app = app
        target = .element(index: elementIndex)
        self.mouseButton = mouseButton
        self.clickCount = clickCount
    }

    init(
        app: String,
        x: Double,
        y: Double,
        mouseButton: ComputerUseMouseButton = .left,
        clickCount: Int = 1
    ) {
        self.app = app
        target = .coordinates(x: x, y: y)
        self.mouseButton = mouseButton
        self.clickCount = clickCount
    }

    enum CodingKeys: String, CodingKey {
        case app
        case target
        case mouseButton = "mouse_button"
        case clickCount = "click_count"
    }
}

enum ComputerUseClickTarget: Codable, Equatable, Sendable {
    case element(index: Int)
    case coordinates(x: Double, y: Double)
}

enum ComputerUseToolCall: Equatable, Sendable {
    case listApps
    case getAppState(app: String, disableDiff: Bool)
    case click(ComputerUseClickRequest)
    case performSecondaryAction(app: String, elementIndex: Int, action: String)
    case setValue(app: String, elementIndex: Int, value: String)
    case selectText(
        app: String,
        elementIndex: Int,
        text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType
    )
    case scroll(app: String, elementIndex: Int, direction: ComputerUseScrollDirection, pages: Double)
    case drag(app: String, fromX: Double, fromY: Double, toX: Double, toY: Double)
    case pressKey(app: String, key: String)
    case typeText(app: String, text: String)
    case setVoiceActivation(enabled: Bool)

    var name: ComputerUseToolName {
        switch self {
        case .listApps:
            .listApps
        case .getAppState:
            .getAppState
        case .click:
            .click
        case .performSecondaryAction:
            .performSecondaryAction
        case .setValue:
            .setValue
        case .selectText:
            .selectText
        case .scroll:
            .scroll
        case .drag:
            .drag
        case .pressKey:
            .pressKey
        case .typeText:
            .typeText
        case .setVoiceActivation:
            .setVoiceActivation
        }
    }

}

enum ComputerUseToolResult: Equatable, Sendable {
    case applications([ComputerUseApplication])
    case appState(ComputerUseAppState)
    case actionCompleted
}

protocol ComputerUseToolServing: Sendable {
    @discardableResult
    func execute(_ call: ComputerUseToolCall) async throws -> ComputerUseToolResult
}
