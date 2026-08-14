import CoreGraphics
import Foundation

struct ComputerUseInputEventTarget: Equatable, Sendable {
    let processIdentifier: Int32
    let windowID: UInt32
    let windowBounds: CGRect
}

/// CGEvent locations are window-local with a flipped (top-left origin) Y axis.
func computerUseWindowEventLocation(
    screenPoint: CGPoint,
    windowBounds: CGRect
) -> CGPoint {
    CGPoint(
        x: screenPoint.x - windowBounds.minX,
        y: windowBounds.height - (screenPoint.y - windowBounds.minY)
    )
}

struct SystemComputerUseInputEvents: ComputerUseInputEventPosting {
    func click(
        at point: CGPoint,
        mouseButton: ComputerUseMouseButton,
        clickCount: Int,
        target: ComputerUseInputEventTarget
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try Self.postMouseEvent(type: .mouseMoved, at: point, target: target)
            try await Task.sleep(for: .milliseconds(16))
            let button = mouseButton.cgButton
            for clickIndex in 1 ... clickCount {
                try Task.checkCancellation()
                guard let down = CGEvent(
                    mouseEventSource: nil,
                    mouseType: mouseButton.downEvent,
                    mouseCursorPosition: point,
                    mouseButton: button
                ),
                    let up = CGEvent(
                        mouseEventSource: nil,
                        mouseType: mouseButton.upEvent,
                        mouseCursorPosition: point,
                        mouseButton: button
                ) else {
                    throw ComputerUseActionError.eventCreationFailed
                }
                down.setIntegerValueField(.mouseEventClickState, value: Int64(clickIndex))
                up.setIntegerValueField(.mouseEventClickState, value: Int64(clickIndex))
                Self.configure(down, screenPoint: point, button: button, target: target)
                Self.configure(up, screenPoint: point, button: button, target: target)
                down.postToPid(target.processIdentifier)
                try await Task.sleep(for: .milliseconds(12))
                up.postToPid(target.processIdentifier)
                if clickIndex < clickCount {
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    func drag(
        from start: CGPoint,
        to end: CGPoint,
        target: ComputerUseInputEventTarget
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try Self.postMouseEvent(type: .mouseMoved, at: start, target: target)
            try await Task.sleep(for: .milliseconds(16))
            try Self.postMouseEvent(type: .leftMouseDown, at: start, target: target)

            var lastPoint = start
            do {
                for step in 1 ... 12 {
                    try Task.checkCancellation()
                    let progress = CGFloat(step) / 12
                    lastPoint = CGPoint(
                        x: start.x + (end.x - start.x) * progress,
                        y: start.y + (end.y - start.y) * progress
                    )
                    try Self.postMouseEvent(type: .leftMouseDragged, at: lastPoint, target: target)
                    try await Task.sleep(for: .milliseconds(12))
                }
                try Self.postMouseEvent(type: .leftMouseUp, at: end, target: target)
            } catch {
                try? Self.postMouseEvent(type: .leftMouseUp, at: lastPoint, target: target)
                throw error
            }
        }
    }

    func scroll(
        at point: CGPoint,
        direction: ComputerUseScrollDirection,
        pages: Double,
        target: ComputerUseInputEventTarget
    ) async throws {
        try await perform {
            guard let move = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                throw ComputerUseActionError.eventCreationFailed
            }
            let delta = direction.eventDelta(pages: pages)
            guard let scroll = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Self.scrollWheelUnits(delta.vertical),
                wheel2: Self.scrollWheelUnits(delta.horizontal),
                wheel3: 0
            ) else {
                throw ComputerUseActionError.eventCreationFailed
            }
            Self.configure(move, screenPoint: point, button: .left, target: target)
            Self.configure(scroll, screenPoint: point, button: .left, target: target)
            move.postToPid(target.processIdentifier)
            scroll.postToPid(target.processIdentifier)
        }
    }

    func pressKey(_ chord: String, pid: Int32) async throws {
        let parsed = try await Self.parseKeyChord(chord)
        try await perform {
            guard let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: parsed.keyCode,
                keyDown: true
            ),
                let up = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: parsed.keyCode,
                    keyDown: false
                ) else {
                throw ComputerUseActionError.eventCreationFailed
            }
            down.flags = parsed.flags
            up.flags = parsed.flags
            down.postToPid(pid)
            do {
                try Task.checkCancellation()
                up.postToPid(pid)
            } catch {
                up.postToPid(pid)
                throw error
            }
        }
    }

    @MainActor
    static func parseKeyChord(_ chord: String) throws -> ComputerUseParsedKeyChord {
        try ComputerUseKeyChord.parse(chord)
    }

    func typeText(_ text: String, pid: Int32) async throws {
        try await perform {
            for chunk in ComputerUseUnicodeEventChunker.chunks(in: text) {
                try Task.checkCancellation()
                try postUnicodeChunk(chunk, pid: pid)
            }
        }
    }

    private func postUnicodeChunk(_ text: String, pid: Int32) throws {
        guard let down = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ),
            let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: false
            ) else {
            throw ComputerUseActionError.eventCreationFailed
        }
        let characters = Array(text.utf16)
        characters.withUnsafeBufferPointer { buffer in
            down.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            up.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        down.postToPid(pid)
        do {
            try Task.checkCancellation()
            up.postToPid(pid)
        } catch {
            up.postToPid(pid)
            throw error
        }
    }

    private func perform(_ operation: @escaping @Sendable () throws -> Void) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try operation()
            try Task.checkCancellation()
        }.value
    }

    private static func postMouseEvent(
        type: CGEventType,
        at point: CGPoint,
        target: ComputerUseInputEventTarget
    ) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ComputerUseActionError.eventCreationFailed
        }
        configure(event, screenPoint: point, button: .left, target: target)
        event.postToPid(target.processIdentifier)
    }

    /// Clamps in floating point first: `Int(_: Double)` traps outside the
    /// `Int` range, and the model controls the page count.
    private static func scrollWheelUnits(_ delta: Double) -> Int32 {
        Int32(min(max(delta.rounded(), Double(Int32.min)), Double(Int32.max)))
    }

    private static func configure(
        _ event: CGEvent,
        screenPoint: CGPoint,
        button: CGMouseButton,
        target: ComputerUseInputEventTarget
    ) {
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        event.setIntegerValueField(.mouseEventSubtype, value: 0)
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointer,
            value: Int64(target.windowID)
        )
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            value: Int64(target.windowID)
        )
        event.location = computerUseWindowEventLocation(
            screenPoint: screenPoint,
            windowBounds: target.windowBounds
        )
    }
}

private extension ComputerUseMouseButton {
    var cgButton: CGMouseButton {
        return switch self {
        case .left: .left
        case .right: .right
        case .middle: .center
        }
    }

    var downEvent: CGEventType {
        switch self {
        case .left: .leftMouseDown
        case .right: .rightMouseDown
        case .middle: .otherMouseDown
        }
    }

    var upEvent: CGEventType {
        switch self {
        case .left: .leftMouseUp
        case .right: .rightMouseUp
        case .middle: .otherMouseUp
        }
    }
}
