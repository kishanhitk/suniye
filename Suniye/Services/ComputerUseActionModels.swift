import CoreGraphics
import Foundation

/// A point relative to the top-left corner of the selected window.
struct ComputerUsePoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

enum ComputerUseMouseButton: String, Codable, Equatable, Sendable {
    case left
    case right
    case middle

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let numericValue = try? container.decode(Int.self) {
            switch numericValue {
            case 0:
                self = .left
            case 1:
                self = .right
            case 2:
                self = .middle
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported mouse button number: \(numericValue)"
                )
            }
            return
        }

        let value = try container.decode(String.self).lowercased()
        switch value {
        case "left", "l":
            self = .left
        case "right", "r":
            self = .right
        case "middle", "m":
            self = .middle
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unsupported mouse button: \(value)"
            )
        }
    }
}

enum ComputerUseTextSelectionType: String, Codable, Equatable, Sendable {
    case text
    case cursorBefore = "cursor_before"
    case cursorAfter = "cursor_after"
}

enum ComputerUseScrollDirection: String, Codable, Equatable, Sendable {
    case up
    case down
    case left
    case right

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "u", "up":
            self = .up
        case "d", "down":
            self = .down
        case "l", "left":
            self = .left
        case "r", "right":
            self = .right
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unsupported scroll direction: \(value)"
            )
        }
    }
}

enum ComputerUseNamedKey: String, Codable, Equatable, Sendable {
    case returnKey = "return"
    case tab
    case escape
    case space
    case delete
    case forwardDelete = "forward_delete"
    case arrowLeft = "arrow_left"
    case arrowRight = "arrow_right"
    case arrowDown = "arrow_down"
    case arrowUp = "arrow_up"
    case home
    case end
    case pageUp = "page_up"
    case pageDown = "page_down"
}

enum ComputerUseKey: Equatable, Sendable {
    case named(ComputerUseNamedKey)
    case character(String)

    var displayName: String {
        switch self {
        case let .named(key):
            return key.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        case let .character(value):
            return value
        }
    }

    static func parseChord(
        _ value: String
    ) throws -> (key: ComputerUseKey, modifiers: ComputerUseKeyModifiers) {
        let parts = value
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let keyPart = parts.last, !keyPart.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Key chord must include a key"
                )
            )
        }

        var modifiers = ComputerUseKeyModifiers()
        for part in parts.dropLast() {
            switch normalizedChordToken(part) {
            case "command", "cmd", "super", "superl", "metaleft", "meta":
                modifiers = modifiers.with(command: true)
            case "option", "alt", "altl":
                modifiers = modifiers.with(option: true)
            case "control", "ctrl", "controll":
                modifiers = modifiers.with(control: true)
            case "shift", "shiftl":
                modifiers = modifiers.with(shift: true)
            case "function", "fn":
                modifiers = modifiers.with(function: true)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Unsupported key modifier: \(part)"
                    )
                )
            }
        }

        let keyValue = String(keyPart)
        let key = try key(named: keyValue)
        switch normalizedChordToken(keyValue) {
        case "greater":
            modifiers = modifiers.with(shift: true)
            return (.character("."), modifiers)
        case "less":
            modifiers = modifiers.with(shift: true)
            return (.character(","), modifiers)
        default:
            return (key, modifiers)
        }
    }

    func referenceChord(with modifiers: ComputerUseKeyModifiers) -> String {
        var parts: [String] = []
        if modifiers.command {
            parts.append("Super_L")
        }
        if modifiers.option {
            parts.append("Alt_L")
        }
        if modifiers.control {
            parts.append("Control_L")
        }
        if modifiers.shift {
            parts.append("Shift_L")
        }
        if modifiers.function {
            parts.append("Fn")
        }
        parts.append(referenceName)
        return parts.joined(separator: "+")
    }

    private var referenceName: String {
        switch self {
        case let .named(key):
            switch key {
            case .returnKey:
                "Return"
            case .tab:
                "Tab"
            case .escape:
                "Escape"
            case .space:
                "space"
            case .delete:
                "BackSpace"
            case .forwardDelete:
                "Delete"
            case .arrowLeft:
                "Left"
            case .arrowRight:
                "Right"
            case .arrowDown:
                "Down"
            case .arrowUp:
                "Up"
            case .home:
                "Home"
            case .end:
                "End"
            case .pageUp:
                "Page_Up"
            case .pageDown:
                "Page_Down"
            }
        case let .character(value):
            value
        }
    }

    private static func key(named value: String) throws -> ComputerUseKey {
        switch normalizedChordToken(value) {
        case "return", "enter":
            return .named(.returnKey)
        case "tab":
            return .named(.tab)
        case "escape", "esc":
            return .named(.escape)
        case "space":
            return .named(.space)
        case "backspace", "deletebackward":
            return .named(.delete)
        case "delete", "forwarddelete":
            return .named(.forwardDelete)
        case "left", "arrowleft":
            return .named(.arrowLeft)
        case "right", "arrowright":
            return .named(.arrowRight)
        case "down", "arrowdown":
            return .named(.arrowDown)
        case "up", "arrowup":
            return .named(.arrowUp)
        case "home":
            return .named(.home)
        case "end":
            return .named(.end)
        case "pageup":
            return .named(.pageUp)
        case "pagedown":
            return .named(.pageDown)
        default:
            return .character(value)
        }
    }

    private static func normalizedChordToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0 != "_" && $0 != "-" && $0 != " " }
    }

}

struct ComputerUseKeyModifiers: Codable, Equatable, Sendable {
    let command: Bool
    let option: Bool
    let control: Bool
    let shift: Bool
    let function: Bool

    init(
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false,
        function: Bool = false
    ) {
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
        self.function = function
    }

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command {
            flags.insert(.maskCommand)
        }
        if option {
            flags.insert(.maskAlternate)
        }
        if control {
            flags.insert(.maskControl)
        }
        if shift {
            flags.insert(.maskShift)
        }
        if function {
            flags.insert(.maskSecondaryFn)
        }
        return flags
    }
}

private extension ComputerUseKeyModifiers {
    func with(
        command: Bool? = nil,
        option: Bool? = nil,
        control: Bool? = nil,
        shift: Bool? = nil,
        function: Bool? = nil
    ) -> ComputerUseKeyModifiers {
        ComputerUseKeyModifiers(
            command: command ?? self.command,
            option: option ?? self.option,
            control: control ?? self.control,
            shift: shift ?? self.shift,
            function: function ?? self.function
        )
    }

    var displayName: String {
        [
            command ? "Command" : nil,
            option ? "Option" : nil,
            control ? "Control" : nil,
            shift ? "Shift" : nil,
            function ? "Function" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " + ")
    }
}

enum ComputerUseActionRisk: String, Codable, Equatable, Hashable, Sendable {
    case click
    case drag
    case keyPress
    case scroll
    case textEntry
    case textSelection
    case secondaryAccessibility
}

enum ComputerUseAction: Codable, Equatable, Sendable {
    case click(
        point: ComputerUsePoint,
        clickCount: Int = 1,
        mouseButton: ComputerUseMouseButton = .left
    )
    case clickElement(
        elementIndex: Int,
        clickCount: Int = 1,
        mouseButton: ComputerUseMouseButton = .left
    )
    case keyPress(key: ComputerUseKey, modifiers: ComputerUseKeyModifiers)
    case scroll(
        elementIndex: Int,
        direction: ComputerUseScrollDirection,
        pages: Double = 1
    )
    case typeText(String)
    case setValue(elementIndex: Int, value: String)
    case drag(
        from: ComputerUsePoint,
        to: ComputerUsePoint
    )
    case selectText(
        elementIndex: Int,
        text: String,
        prefix: String? = nil,
        suffix: String? = nil,
        selectionType: ComputerUseTextSelectionType = .text
    )
    case secondaryAction(elementIndex: Int, action: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case x
        case y
        case key
        case modifiers
        case clickCount = "click_count"
        case mouseButton = "mouse_button"
        case text
        case value
        case fromX = "from_x"
        case fromY = "from_y"
        case toX = "to_x"
        case toY = "to_y"
        case elementIndex = "element_index"
        case prefix
        case suffix
        case selectionType = "selection_type"
        case action
        case direction
        case pages
    }

    private enum Kind: String, Codable {
        case click
        case keyPress = "press_key"
        case scroll
        case typeText = "type_text"
        case setValue = "set_value"
        case drag
        case selectText = "select_text"
        case secondaryAction = "perform_secondary_action"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .click:
            if let elementIndex = try container.decodeIfPresent(Int.self, forKey: .elementIndex) {
                self = .clickElement(
                    elementIndex: elementIndex,
                    clickCount: try container.decodeIfPresent(Int.self, forKey: .clickCount) ?? 1,
                    mouseButton: try container.decodeIfPresent(
                        ComputerUseMouseButton.self,
                        forKey: .mouseButton
                    ) ?? .left
                )
                return
            }
            self = .click(
                point: ComputerUsePoint(
                    x: try container.decode(Double.self, forKey: .x),
                    y: try container.decode(Double.self, forKey: .y)
                ),
                clickCount: try container.decodeIfPresent(Int.self, forKey: .clickCount) ?? 1,
                mouseButton: try container.decodeIfPresent(
                    ComputerUseMouseButton.self,
                    forKey: .mouseButton
                ) ?? .left
            )
        case .keyPress:
            let parsed = try ComputerUseKey.parseChord(
                container.decode(String.self, forKey: .key)
            )
            let modifiers = try container.decodeIfPresent(
                ComputerUseKeyModifiers.self,
                forKey: .modifiers
            ) ?? parsed.modifiers
            self = .keyPress(
                key: parsed.key,
                modifiers: modifiers
            )
        case .scroll:
            self = .scroll(
                elementIndex: try container.decode(Int.self, forKey: .elementIndex),
                direction: try container.decode(ComputerUseScrollDirection.self, forKey: .direction),
                pages: try container.decodeIfPresent(Double.self, forKey: .pages) ?? 1
            )
        case .typeText:
            self = .typeText(try container.decode(String.self, forKey: .text))
        case .setValue:
            self = .setValue(
                elementIndex: try container.decode(Int.self, forKey: .elementIndex),
                value: try container.decode(String.self, forKey: .value)
            )
        case .drag:
            self = .drag(
                from: ComputerUsePoint(
                    x: try container.decode(Double.self, forKey: .fromX),
                    y: try container.decode(Double.self, forKey: .fromY)
                ),
                to: ComputerUsePoint(
                    x: try container.decode(Double.self, forKey: .toX),
                    y: try container.decode(Double.self, forKey: .toY)
                )
            )
        case .selectText:
            self = .selectText(
                elementIndex: try container.decode(Int.self, forKey: .elementIndex),
                text: try container.decode(String.self, forKey: .text),
                prefix: try container.decodeIfPresent(String.self, forKey: .prefix),
                suffix: try container.decodeIfPresent(String.self, forKey: .suffix),
                selectionType: try container.decodeIfPresent(
                    ComputerUseTextSelectionType.self,
                    forKey: .selectionType
                ) ?? .text
            )
        case .secondaryAction:
            self = .secondaryAction(
                elementIndex: try container.decode(Int.self, forKey: .elementIndex),
                action: try container.decode(String.self, forKey: .action)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .click(point, clickCount, mouseButton):
            try container.encode(Kind.click, forKey: .kind)
            try container.encode(point.x, forKey: .x)
            try container.encode(point.y, forKey: .y)
            try container.encode(clickCount, forKey: .clickCount)
            try container.encode(mouseButton, forKey: .mouseButton)
        case let .clickElement(elementIndex, clickCount, mouseButton):
            try container.encode(Kind.click, forKey: .kind)
            try container.encode(elementIndex, forKey: .elementIndex)
            try container.encode(clickCount, forKey: .clickCount)
            try container.encode(mouseButton, forKey: .mouseButton)
        case let .keyPress(key, modifiers):
            try container.encode(Kind.keyPress, forKey: .kind)
            try container.encode(key.referenceChord(with: modifiers), forKey: .key)
        case let .scroll(elementIndex, direction, pages):
            try container.encode(Kind.scroll, forKey: .kind)
            try container.encode(elementIndex, forKey: .elementIndex)
            try container.encode(direction, forKey: .direction)
            try container.encode(pages, forKey: .pages)
        case let .typeText(text):
            try container.encode(Kind.typeText, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .setValue(elementIndex, value):
            try container.encode(Kind.setValue, forKey: .kind)
            try container.encode(elementIndex, forKey: .elementIndex)
            try container.encode(value, forKey: .value)
        case let .drag(from, to):
            try container.encode(Kind.drag, forKey: .kind)
            try container.encode(from.x, forKey: .fromX)
            try container.encode(from.y, forKey: .fromY)
            try container.encode(to.x, forKey: .toX)
            try container.encode(to.y, forKey: .toY)
        case let .selectText(elementIndex, text, prefix, suffix, selectionType):
            try container.encode(Kind.selectText, forKey: .kind)
            try container.encode(elementIndex, forKey: .elementIndex)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(prefix, forKey: .prefix)
            try container.encodeIfPresent(suffix, forKey: .suffix)
            try container.encode(selectionType, forKey: .selectionType)
        case let .secondaryAction(elementIndex, action):
            try container.encode(Kind.secondaryAction, forKey: .kind)
            try container.encode(elementIndex, forKey: .elementIndex)
            try container.encode(action, forKey: .action)
        }
    }

    var risk: ComputerUseActionRisk {
        switch self {
        case .click, .clickElement:
            return .click
        case .drag:
            return .drag
        case .keyPress:
            return .keyPress
        case .scroll:
            return .scroll
        case .typeText, .setValue:
            return .textEntry
        case .selectText:
            return .textSelection
        case .secondaryAction:
            return .secondaryAccessibility
        }
    }

    var summary: String {
        switch self {
        case let .click(point, clickCount, mouseButton):
            let count = clickCount == 1 ? "" : " x\(clickCount)"
            return "Click \(mouseButton.rawValue)\(count) at \(Int(point.x)), \(Int(point.y))"
        case let .clickElement(elementIndex, clickCount, mouseButton):
            let count = clickCount == 1 ? "" : " x\(clickCount)"
            return "Click \(mouseButton.rawValue)\(count) on element \(elementIndex)"
        case let .keyPress(key, modifiers):
            let prefix = modifiers.displayName.isEmpty ? "" : "\(modifiers.displayName) + "
            return "Press \(prefix)\(key.displayName)"
        case let .scroll(elementIndex, direction, pages):
            return "Scroll \(direction.rawValue) \(pages)x on element \(elementIndex)"
        case let .typeText(text):
            return "Type \(text.count) characters"
        case let .setValue(elementIndex, value):
            return "Set value of element \(elementIndex) (\(value.count) characters)"
        case let .drag(from, to):
            return "Drag from \(Int(from.x)), \(Int(from.y)) to \(Int(to.x)), \(Int(to.y))"
        case let .selectText(elementIndex, text, _, _, selectionType):
            return "Select \(selectionType.rawValue) in element \(elementIndex) (\(text.count) characters)"
        case let .secondaryAction(elementIndex, action):
            return "\(action) on element \(elementIndex)"
        }
    }

}

enum ComputerUseApprovalScope: String, Codable, Equatable, Hashable, Sendable {
    case once
    case session
    case always
}

struct ComputerUseApprovalRequest: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let action: ComputerUseAction
    let target: ComputerUseTarget
    let risk: ComputerUseActionRisk
    let sessionID: UUID
    let observationGeneration: UInt64
    let allowedScopes: Set<ComputerUseApprovalScope>

    init(
        id: UUID,
        action: ComputerUseAction,
        target: ComputerUseTarget,
        risk: ComputerUseActionRisk,
        sessionID: UUID = UUID(),
        observationGeneration: UInt64 = 0,
        allowedScopes: Set<ComputerUseApprovalScope> = [.once]
    ) {
        self.id = id
        self.action = action
        self.target = target
        self.risk = risk
        self.sessionID = sessionID
        self.observationGeneration = observationGeneration
        self.allowedScopes = allowedScopes
    }

}

struct ComputerUseApprovalGrant: Codable, Equatable, Sendable {
    let requestID: UUID
    let scope: ComputerUseApprovalScope
    let applicationID: String
    let windowID: UInt32
    let observationGeneration: UInt64
    let action: ComputerUseAction
    let sessionID: UUID

    init(
        requestID: UUID,
        scope: ComputerUseApprovalScope,
        applicationID: String,
        windowID: UInt32,
        observationGeneration: UInt64,
        action: ComputerUseAction,
        sessionID: UUID = UUID()
    ) {
        self.requestID = requestID
        self.scope = scope
        self.applicationID = applicationID
        self.windowID = windowID
        self.observationGeneration = observationGeneration
        self.action = action
        self.sessionID = sessionID
    }
}

struct ComputerUseActionResult: Codable, Equatable, Sendable {
    let action: ComputerUseAction
    let target: ComputerUseTarget
    let completedAt: Date
}

enum ComputerUseActionError: LocalizedError, Equatable, Sendable {
    case cancelled
    case approvalRequired
    case staleApproval
    case permissionRequired
    case targetActivationFailed
    case invalidAction(String)
    case unsupportedKey(String)
    case eventCreationFailed
    case secondaryActionFailed(String)
    case accessibilityValueActionFailed(String)
    case textSelectionFailed(String)
    case textInsertionFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Computer Use action was canceled."
        case .approvalRequired:
            return "This action requires a current approval."
        case .staleApproval:
            return "The approval no longer matches the current app state."
        case .permissionRequired:
            return "Accessibility permission is required to control the selected app."
        case .targetActivationFailed:
            return "The target application or window could not be brought forward."
        case let .invalidAction(message):
            return "The action is invalid: \(message)."
        case let .unsupportedKey(key):
            return "The key is not supported: \(key)."
        case .eventCreationFailed:
            return "macOS could not create the requested input event."
        case let .secondaryActionFailed(action):
            return "The Accessibility action failed: \(action)."
        case let .accessibilityValueActionFailed(message):
            return "The Accessibility value action failed: \(message)."
        case let .textSelectionFailed(message):
            return "Text selection failed: \(message)."
        case let .textInsertionFailed(message):
            return "Text entry failed: \(message)."
        }
    }
}

protocol ComputerUseInputEventPosting {
    func click(
        at point: ComputerUsePoint,
        mouseButton: ComputerUseMouseButton,
        clickCount: Int,
        cancellation: ComputerUseCancellationToken
    ) throws
    func drag(
        from start: ComputerUsePoint,
        to end: ComputerUsePoint,
        cancellation: ComputerUseCancellationToken
    ) throws
    func keyPress(
        key: ComputerUseKey,
        modifiers: ComputerUseKeyModifiers,
        targetProcessIdentifier: Int32,
        cancellation: ComputerUseCancellationToken
    ) throws
    func scroll(
        horizontal: Double,
        vertical: Double,
        at point: ComputerUsePoint?,
        cancellation: ComputerUseCancellationToken
    ) throws
}

protocol ComputerUseSecondaryActionPerforming {
    func perform(
        action: String,
        elementIndex: Int,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws
}

protocol ComputerUseValueActionPerforming {
    func setValue(
        _ value: String,
        elementIndex: Int,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws

    func selectText(
        _ text: String,
        elementIndex: Int,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws
}

protocol ComputerUseActionServicing {
    func execute(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        approval: ComputerUseApprovalGrant,
        requestID: UUID,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseActionResult
}
