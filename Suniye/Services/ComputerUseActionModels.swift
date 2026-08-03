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

enum ComputerUseMouseButton: String, Codable, Equatable, Sendable, CaseIterable {
    case left
    case right
    case middle

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).lowercased()
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

enum ComputerUseTextSelectionType: String, Codable, Equatable, Sendable, CaseIterable {
    case text
    case cursorBefore = "cursor_before"
    case cursorAfter = "cursor_after"
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

enum ComputerUseKey: Codable, Equatable, Sendable {
    case named(ComputerUseNamedKey)
    case character(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case named
        case character
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .named:
            self = .named(try container.decode(ComputerUseNamedKey.self, forKey: .value))
        case .character:
            self = .character(try container.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .named(key):
            try container.encode(Kind.named, forKey: .kind)
            try container.encode(key, forKey: .value)
        case let .character(value):
            try container.encode(Kind.character, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    var displayName: String {
        switch self {
        case let .named(key):
            return key.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        case let .character(value):
            return value
        }
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

enum ComputerUseSemanticAction: String, Codable, Equatable, Sendable, CaseIterable {
    case press = "AXPress"
    case increment = "AXIncrement"
    case decrement = "AXDecrement"
    case confirm = "AXConfirm"
    case cancel = "AXCancel"
    case showMenu = "AXShowMenu"
    case pick = "AXPick"
    case raise = "AXRaise"
}

enum ComputerUseActionRisk: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case click
    case drag
    case keyPress
    case scroll
    case textEntry
    case textSelection
    case semanticAccessibility

    var title: String {
        switch self {
        case .click:
            return "Click"
        case .drag:
            return "Drag"
        case .keyPress:
            return "Key press"
        case .scroll:
            return "Scroll"
        case .textEntry:
            return "Text entry"
        case .textSelection:
            return "Text selection"
        case .semanticAccessibility:
            return "Accessibility action"
        }
    }
}

enum ComputerUseAction: Codable, Equatable, Sendable {
    case click(
        point: ComputerUsePoint,
        clickCount: Int = 1,
        mouseButton: ComputerUseMouseButton = .left,
        screenshotID: String? = nil
    )
    case clickElement(
        elementIndex: Int,
        clickCount: Int = 1,
        mouseButton: ComputerUseMouseButton = .left,
        screenshotID: String? = nil
    )
    case keyPress(key: ComputerUseKey, modifiers: ComputerUseKeyModifiers)
    case scroll(
        horizontal: Double,
        vertical: Double,
        point: ComputerUsePoint? = nil,
        screenshotID: String? = nil
    )
    case typeText(String)
    case setValue(elementIndex: Int, value: String)
    case drag(
        from: ComputerUsePoint,
        to: ComputerUsePoint,
        screenshotID: String? = nil
    )
    case selectText(
        elementIndex: Int,
        text: String,
        prefix: String? = nil,
        suffix: String? = nil,
        selectionType: ComputerUseTextSelectionType = .text
    )
    case secondaryAction(elementIndex: Int, action: String)
    case semantic(elementIndex: Int, action: ComputerUseSemanticAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case x
        case y
        case key
        case modifiers
        case horizontal
        case vertical
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
        case screenshotID = "screenshotId"
    }

    private enum Kind: String, Codable {
        case click
        case keyPress = "key_press"
        case scroll
        case typeText = "type_text"
        case setValue = "set_value"
        case drag
        case selectText = "select_text"
        case secondaryAction = "perform_secondary_action"
        case semantic
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
                    ) ?? .left,
                    screenshotID: try container.decodeIfPresent(String.self, forKey: .screenshotID)
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
                ) ?? .left,
                screenshotID: try container.decodeIfPresent(String.self, forKey: .screenshotID)
            )
        case .keyPress:
            self = .keyPress(
                key: try container.decode(ComputerUseKey.self, forKey: .key),
                modifiers: try container.decodeIfPresent(
                    ComputerUseKeyModifiers.self,
                    forKey: .modifiers
                ) ?? ComputerUseKeyModifiers()
            )
        case .scroll:
            let pointX = try container.decodeIfPresent(Double.self, forKey: .x)
            let pointY = try container.decodeIfPresent(Double.self, forKey: .y)
            guard (pointX == nil) == (pointY == nil) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .x,
                    in: container,
                    debugDescription: "x and y must be provided together for a positioned scroll"
                )
            }
            let point: ComputerUsePoint?
            if let pointX, let pointY {
                point = ComputerUsePoint(x: pointX, y: pointY)
            } else {
                point = nil
            }
            self = .scroll(
                horizontal: try container.decode(Double.self, forKey: .horizontal),
                vertical: try container.decode(Double.self, forKey: .vertical),
                point: point,
                screenshotID: try container.decodeIfPresent(String.self, forKey: .screenshotID)
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
                ),
                screenshotID: try container.decodeIfPresent(String.self, forKey: .screenshotID)
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
        case .semantic:
            self = .semantic(
                elementIndex: try container.decode(Int.self, forKey: .elementIndex),
                action: try container.decode(ComputerUseSemanticAction.self, forKey: .action)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .click(point, clickCount, mouseButton, screenshotID):
            try container.encode(Kind.click, forKey: .kind)
            try container.encode(point.x, forKey: .x)
            try container.encode(point.y, forKey: .y)
            try container.encode(clickCount, forKey: .clickCount)
            try container.encode(mouseButton, forKey: .mouseButton)
            try container.encodeIfPresent(screenshotID, forKey: .screenshotID)
        case let .clickElement(elementIndex, clickCount, mouseButton, screenshotID):
            try container.encode(Kind.click, forKey: .kind)
            try container.encode(elementIndex, forKey: .elementIndex)
            try container.encode(clickCount, forKey: .clickCount)
            try container.encode(mouseButton, forKey: .mouseButton)
            try container.encodeIfPresent(screenshotID, forKey: .screenshotID)
        case let .keyPress(key, modifiers):
            try container.encode(Kind.keyPress, forKey: .kind)
            try container.encode(key, forKey: .key)
            try container.encode(modifiers, forKey: .modifiers)
        case let .scroll(horizontal, vertical, point, screenshotID):
            try container.encode(Kind.scroll, forKey: .kind)
            try container.encode(horizontal, forKey: .horizontal)
            try container.encode(vertical, forKey: .vertical)
            if let point {
                try container.encode(point.x, forKey: .x)
                try container.encode(point.y, forKey: .y)
            }
            try container.encodeIfPresent(screenshotID, forKey: .screenshotID)
        case let .typeText(text):
            try container.encode(Kind.typeText, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .setValue(elementIndex, value):
            try container.encode(Kind.setValue, forKey: .kind)
            try container.encode(elementIndex, forKey: .elementIndex)
            try container.encode(value, forKey: .value)
        case let .drag(from, to, screenshotID):
            try container.encode(Kind.drag, forKey: .kind)
            try container.encode(from.x, forKey: .fromX)
            try container.encode(from.y, forKey: .fromY)
            try container.encode(to.x, forKey: .toX)
            try container.encode(to.y, forKey: .toY)
            try container.encodeIfPresent(screenshotID, forKey: .screenshotID)
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
        case let .semantic(elementIndex, action):
            try container.encode(Kind.semantic, forKey: .kind)
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
            return .semanticAccessibility
        case .semantic:
            return .semanticAccessibility
        }
    }

    var summary: String {
        switch self {
        case let .click(point, clickCount, mouseButton, _):
            let count = clickCount == 1 ? "" : " x\(clickCount)"
            return "Click \(mouseButton.rawValue)\(count) at \(Int(point.x)), \(Int(point.y))"
        case let .clickElement(elementIndex, clickCount, mouseButton, _):
            let count = clickCount == 1 ? "" : " x\(clickCount)"
            return "Click \(mouseButton.rawValue)\(count) on element \(elementIndex)"
        case let .keyPress(key, modifiers):
            let prefix = modifiers.displayName.isEmpty ? "" : "\(modifiers.displayName) + "
            return "Press \(prefix)\(key.displayName)"
        case let .scroll(horizontal, vertical, point, _):
            if let point {
                return "Scroll at \(Int(point.x)), \(Int(point.y)): \(Int(horizontal)), \(Int(vertical))"
            }
            return "Scroll \(Int(horizontal)), \(Int(vertical))"
        case let .typeText(text):
            return "Type \(text.count) characters"
        case let .setValue(elementIndex, value):
            return "Set value of element \(elementIndex) (\(value.count) characters)"
        case let .drag(from, to, _):
            return "Drag from \(Int(from.x)), \(Int(from.y)) to \(Int(to.x)), \(Int(to.y))"
        case let .selectText(elementIndex, text, _, _, selectionType):
            return "Select \(selectionType.rawValue) in element \(elementIndex) (\(text.count) characters)"
        case let .secondaryAction(elementIndex, action):
            return "\(action) on element \(elementIndex)"
        case let .semantic(elementIndex, action):
            return "\(action.rawValue) on element \(elementIndex)"
        }
    }

    var textPreview: String? {
        switch self {
        case let .typeText(text), let .setValue(_, text), let .selectText(_, text, _, _, _):
            return text
        default:
            return nil
        }
    }
}

private extension ComputerUseKeyModifiers {
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

enum ComputerUseApprovalScope: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case once
    case session
    case always

    var title: String {
        switch self {
        case .once:
            return "Allow Once"
        case .session:
            return "Allow for Session"
        case .always:
            return "Always Allow"
        }
    }

    var isPersistent: Bool {
        self != .once
    }
}

enum ComputerUseApprovalDecision: Equatable, Sendable {
    case allowOnce
    case allowForSession
    case allowAlways
    case deny
    case stopSession

    var scope: ComputerUseApprovalScope? {
        switch self {
        case .allowOnce:
            return .once
        case .allowForSession:
            return .session
        case .allowAlways:
            return .always
        case .deny, .stopSession:
            return nil
        }
    }
}

struct ComputerUseApprovalRequest: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let action: ComputerUseAction
    let target: ComputerUseTarget
    let risk: ComputerUseActionRisk
    let reason: String
    let sessionID: UUID
    let observationGeneration: UInt64
    let allowedScopes: Set<ComputerUseApprovalScope>

    init(
        id: UUID,
        action: ComputerUseAction,
        target: ComputerUseTarget,
        risk: ComputerUseActionRisk,
        reason: String,
        sessionID: UUID = UUID(),
        observationGeneration: UInt64 = 0,
        allowedScopes: Set<ComputerUseApprovalScope> = [.once]
    ) {
        self.id = id
        self.action = action
        self.target = target
        self.risk = risk
        self.reason = reason
        self.sessionID = sessionID
        self.observationGeneration = observationGeneration
        self.allowedScopes = allowedScopes
    }

    var textPreview: String? {
        guard let text = action.textPreview else {
            return nil
        }
        return "(\(text.count) characters hidden)"
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
    case semanticActionFailed(String)
    case accessibilityValueActionFailed(String)
    case textSelectionFailed(String)
    case textInsertionFailed(String)
    case staleScreenshot

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
        case let .semanticActionFailed(action):
            return "The Accessibility action failed: \(action)."
        case let .accessibilityValueActionFailed(message):
            return "The Accessibility value action failed: \(message)."
        case let .textSelectionFailed(message):
            return "Text selection failed: \(message)."
        case let .textInsertionFailed(message):
            return "Text entry failed: \(message)."
        case .staleScreenshot:
            return "The screenshot used for this action is no longer current."
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
        cancellation: ComputerUseCancellationToken
    ) throws
    func scroll(
        horizontal: Double,
        vertical: Double,
        at point: ComputerUsePoint?,
        cancellation: ComputerUseCancellationToken
    ) throws
}

protocol ComputerUseSemanticActionPerforming {
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
