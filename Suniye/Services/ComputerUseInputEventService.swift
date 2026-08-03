import CoreGraphics
import Foundation

struct SystemComputerUseInputEventPoster: ComputerUseInputEventPosting {
    func click(
        at point: ComputerUsePoint,
        mouseButton: ComputerUseMouseButton,
        clickCount: Int,
        cancellation: ComputerUseCancellationToken
    ) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }

        let button = mouseButton.cgButton
        for _ in 0 ..< clickCount {
            guard let down = CGEvent(
                mouseEventSource: nil,
                mouseType: mouseButton.downEvent,
                mouseCursorPosition: point.cgPoint,
                mouseButton: button
            ),
            let up = CGEvent(
                mouseEventSource: nil,
                mouseType: mouseButton.upEvent,
                mouseCursorPosition: point.cgPoint,
                mouseButton: button
            ) else {
                throw ComputerUseActionError.eventCreationFailed
            }

            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            guard !cancellation.isCancelled else {
                throw ComputerUseActionError.cancelled
            }
        }
    }

    func drag(
        from start: ComputerUsePoint,
        to end: ComputerUsePoint,
        cancellation: ComputerUseCancellationToken
    ) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }

        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: start.cgPoint,
            mouseButton: .left
        ),
        let dragged = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: end.cgPoint,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: end.cgPoint,
            mouseButton: .left
        ) else {
            throw ComputerUseActionError.eventCreationFailed
        }

        down.post(tap: .cghidEventTap)
        guard !cancellation.isCancelled else {
            up.post(tap: .cghidEventTap)
            throw ComputerUseActionError.cancelled
        }
        dragged.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func keyPress(
        key: ComputerUseKey,
        modifiers: ComputerUseKeyModifiers,
        targetProcessIdentifier: Int32,
        cancellation: ComputerUseCancellationToken
    ) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }

        guard let keyCode = keyCode(for: key) else {
            throw ComputerUseActionError.unsupportedKey(key.displayName)
        }
        guard let down = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: true
        ),
        let up = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: false
        ) else {
            throw ComputerUseActionError.eventCreationFailed
        }

        let flags = modifiers.cgEventFlags
        down.flags = flags
        up.flags = flags
        down.postToPid(targetProcessIdentifier)
        guard !cancellation.isCancelled else {
            up.postToPid(targetProcessIdentifier)
            throw ComputerUseActionError.cancelled
        }
        up.postToPid(targetProcessIdentifier)
    }

    func scroll(
        horizontal: Double,
        vertical: Double,
        at point: ComputerUsePoint?,
        cancellation: ComputerUseCancellationToken
    ) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        guard horizontal.isFinite, vertical.isFinite else {
            throw ComputerUseActionError.invalidAction("scroll values must be finite")
        }

        if let point {
            guard let move = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point.cgPoint,
                mouseButton: .left
            ) else {
                throw ComputerUseActionError.eventCreationFailed
            }
            move.post(tap: .cghidEventTap)
        }

        let horizontalQuantity = Int32(clamping: Int(horizontal.rounded()))
        let verticalQuantity = Int32(clamping: Int(vertical.rounded()))
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: verticalQuantity,
            wheel2: horizontalQuantity,
            wheel3: 0
        ) else {
            throw ComputerUseActionError.eventCreationFailed
        }

        event.post(tap: .cghidEventTap)
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
    }

    private func keyCode(for key: ComputerUseKey) -> CGKeyCode? {
        switch key {
        case let .character(value):
            if value.count == 1 {
                return TextInsertionService.virtualKeyCode(for: value)
            }
            switch normalizedKeyName(value) {
            case "period", "dot":
                return TextInsertionService.virtualKeyCode(for: ".")
            case "comma":
                return TextInsertionService.virtualKeyCode(for: ",")
            case "slash":
                return TextInsertionService.virtualKeyCode(for: "/")
            case "backslash":
                return TextInsertionService.virtualKeyCode(for: "\\")
            case "semicolon":
                return TextInsertionService.virtualKeyCode(for: ";")
            case "apostrophe", "quote":
                return TextInsertionService.virtualKeyCode(for: "'")
            case "bracketleft", "leftbracket":
                return TextInsertionService.virtualKeyCode(for: "[")
            case "bracketright", "rightbracket":
                return TextInsertionService.virtualKeyCode(for: "]")
            case "minus", "hyphen":
                return TextInsertionService.virtualKeyCode(for: "-")
            case "equal", "equals":
                return TextInsertionService.virtualKeyCode(for: "=")
            case "grave", "backquote", "backtick":
                return TextInsertionService.virtualKeyCode(for: "`")
            case "kp0", "numpad0":
                return 82
            case "kp1", "numpad1":
                return 83
            case "kp2", "numpad2":
                return 84
            case "kp3", "numpad3":
                return 85
            case "kp4", "numpad4":
                return 86
            case "kp5", "numpad5":
                return 87
            case "kp6", "numpad6":
                return 88
            case "kp7", "numpad7":
                return 89
            case "kp8", "numpad8":
                return 91
            case "kp9", "numpad9":
                return 92
            case "f1":
                return 122
            case "f2":
                return 120
            case "f3":
                return 99
            case "f4":
                return 118
            case "f5":
                return 96
            case "f6":
                return 97
            case "f7":
                return 98
            case "f8":
                return 100
            case "f9":
                return 101
            case "f10":
                return 109
            case "f11":
                return 103
            case "f12":
                return 111
            default:
                return nil
            }
        case let .named(namedKey):
            switch namedKey {
            case .returnKey:
                return 36
            case .tab:
                return 48
            case .escape:
                return 53
            case .space:
                return 49
            case .delete:
                return 51
            case .forwardDelete:
                return 117
            case .arrowLeft:
                return 123
            case .arrowRight:
                return 124
            case .arrowDown:
                return 125
            case .arrowUp:
                return 126
            case .home:
                return 115
            case .end:
                return 119
            case .pageUp:
                return 116
            case .pageDown:
                return 121
            }
        }
    }

    private func normalizedKeyName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0 != "_" && $0 != "-" && $0 != " " }
    }
}

private extension ComputerUseMouseButton {
    var cgButton: CGMouseButton {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .center
        }
    }

    var downEvent: CGEventType {
        switch self {
        case .left:
            return .leftMouseDown
        case .right:
            return .rightMouseDown
        case .middle:
            return .otherMouseDown
        }
    }

    var upEvent: CGEventType {
        switch self {
        case .left:
            return .leftMouseUp
        case .right:
            return .rightMouseUp
        case .middle:
            return .otherMouseUp
        }
    }
}
