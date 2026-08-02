import CoreGraphics
import Foundation

struct ComputerUsePoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
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

enum ComputerUseActionRisk: String, Codable, Equatable, Sendable {
    case click
    case keyPress
    case scroll
    case textEntry
    case semanticAccessibility

    var title: String {
        switch self {
        case .click:
            return "Click"
        case .keyPress:
            return "Key press"
        case .scroll:
            return "Scroll"
        case .textEntry:
            return "Text entry"
        case .semanticAccessibility:
            return "Accessibility action"
        }
    }
}

enum ComputerUseAction: Codable, Equatable, Sendable {
    case click(point: ComputerUsePoint)
    case keyPress(key: ComputerUseKey, modifiers: ComputerUseKeyModifiers)
    case scroll(horizontal: Double, vertical: Double)
    case typeText(String)
    case semantic(elementIndex: Int, action: ComputerUseSemanticAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case x
        case y
        case key
        case modifiers
        case horizontal
        case vertical
        case text
        case elementIndex
        case action
    }

    private enum Kind: String, Codable {
        case click
        case keyPress = "key_press"
        case scroll
        case typeText = "type_text"
        case semantic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .click:
            self = .click(
                point: ComputerUsePoint(
                    x: try container.decode(Double.self, forKey: .x),
                    y: try container.decode(Double.self, forKey: .y)
                )
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
            self = .scroll(
                horizontal: try container.decode(Double.self, forKey: .horizontal),
                vertical: try container.decode(Double.self, forKey: .vertical)
            )
        case .typeText:
            self = .typeText(try container.decode(String.self, forKey: .text))
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
        case let .click(point):
            try container.encode(Kind.click, forKey: .kind)
            try container.encode(point.x, forKey: .x)
            try container.encode(point.y, forKey: .y)
        case let .keyPress(key, modifiers):
            try container.encode(Kind.keyPress, forKey: .kind)
            try container.encode(key, forKey: .key)
            try container.encode(modifiers, forKey: .modifiers)
        case let .scroll(horizontal, vertical):
            try container.encode(Kind.scroll, forKey: .kind)
            try container.encode(horizontal, forKey: .horizontal)
            try container.encode(vertical, forKey: .vertical)
        case let .typeText(text):
            try container.encode(Kind.typeText, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .semantic(elementIndex, action):
            try container.encode(Kind.semantic, forKey: .kind)
            try container.encode(elementIndex, forKey: .elementIndex)
            try container.encode(action, forKey: .action)
        }
    }

    var risk: ComputerUseActionRisk {
        switch self {
        case .click:
            return .click
        case .keyPress:
            return .keyPress
        case .scroll:
            return .scroll
        case .typeText:
            return .textEntry
        case .semantic:
            return .semanticAccessibility
        }
    }

    var summary: String {
        switch self {
        case let .click(point):
            return "Click at \(Int(point.x)), \(Int(point.y))"
        case let .keyPress(key, modifiers):
            let prefix = modifiers.displayName.isEmpty ? "" : "\(modifiers.displayName) + "
            return "Press \(prefix)\(key.displayName)"
        case let .scroll(horizontal, vertical):
            return "Scroll \(Int(horizontal)), \(Int(vertical))"
        case let .typeText(text):
            return "Type \(text.count) characters"
        case let .semantic(elementIndex, action):
            return "\(action.rawValue) on element \(elementIndex)"
        }
    }

    var textPreview: String? {
        guard case let .typeText(text) = self else {
            return nil
        }
        return text
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

enum ComputerUseApprovalScope: String, Codable, Equatable, Sendable {
    case once
}

enum ComputerUseApprovalDecision: Equatable, Sendable {
    case allowOnce
    case deny
    case stopSession
}

struct ComputerUseApprovalRequest: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let action: ComputerUseAction
    let target: ComputerUseTarget
    let risk: ComputerUseActionRisk
    let reason: String

    var textPreview: String? {
        action.textPreview
    }
}

struct ComputerUseApprovalGrant: Codable, Equatable, Sendable {
    let requestID: UUID
    let scope: ComputerUseApprovalScope
    let applicationID: String
    let windowID: UInt32
    let observationGeneration: UInt64
    let action: ComputerUseAction
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
    case targetNotFrontmost
    case invalidAction(String)
    case unsupportedKey(String)
    case eventCreationFailed
    case semanticActionFailed(String)
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
        case .targetNotFrontmost:
            return "The selected app is no longer the frontmost app."
        case let .invalidAction(message):
            return "The action is invalid: \(message)."
        case let .unsupportedKey(key):
            return "The key is not supported: \(key)."
        case .eventCreationFailed:
            return "macOS could not create the requested input event."
        case let .semanticActionFailed(action):
            return "The Accessibility action failed: \(action)."
        case let .textInsertionFailed(message):
            return "Text entry failed: \(message)."
        }
    }
}

protocol ComputerUseInputEventPosting {
    func click(at point: ComputerUsePoint, cancellation: ComputerUseCancellationToken) throws
    func keyPress(
        key: ComputerUseKey,
        modifiers: ComputerUseKeyModifiers,
        cancellation: ComputerUseCancellationToken
    ) throws
    func scroll(
        horizontal: Double,
        vertical: Double,
        cancellation: ComputerUseCancellationToken
    ) throws
}

protocol ComputerUseSemanticActionPerforming {
    func perform(
        action: ComputerUseSemanticAction,
        elementIndex: Int,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws
}

protocol ComputerUseTargetValidating {
    func isCurrent(target: ComputerUseTarget) -> Bool
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
