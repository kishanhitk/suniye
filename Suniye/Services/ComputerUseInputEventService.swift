import CoreGraphics
import Foundation

struct SystemComputerUseInputEventPoster: ComputerUseInputEventPosting {
    func click(at point: ComputerUsePoint, cancellation: ComputerUseCancellationToken) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }

        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point.cgPoint,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point.cgPoint,
            mouseButton: .left
        ) else {
            throw ComputerUseActionError.eventCreationFailed
        }

        down.post(tap: .cghidEventTap)
        defer {
            up.post(tap: .cghidEventTap)
        }

        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
    }

    func keyPress(
        key: ComputerUseKey,
        modifiers: ComputerUseKeyModifiers,
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
        down.post(tap: .cghidEventTap)
        guard !cancellation.isCancelled else {
            up.post(tap: .cghidEventTap)
            throw ComputerUseActionError.cancelled
        }
        up.post(tap: .cghidEventTap)
    }

    func scroll(
        horizontal: Double,
        vertical: Double,
        cancellation: ComputerUseCancellationToken
    ) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        guard horizontal.isFinite, vertical.isFinite else {
            throw ComputerUseActionError.invalidAction("scroll values must be finite")
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
            guard value.count == 1 else {
                return nil
            }
            return TextInsertionService.virtualKeyCode(for: value)
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
}
