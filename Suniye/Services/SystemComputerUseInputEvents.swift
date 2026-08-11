import CoreGraphics
import Foundation

struct SystemComputerUseInputEvents: ComputerUseInputEventPosting {
    func click(
        at point: CGPoint,
        mouseButton: ComputerUseMouseButton,
        clickCount: Int,
        pid: Int32
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try Self.postMouseEvent(type: .mouseMoved, at: point, pid: pid)
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
                down.postToPid(pid)
                try await Task.sleep(for: .milliseconds(12))
                up.postToPid(pid)
                if clickIndex < clickCount {
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    func drag(from start: CGPoint, to end: CGPoint, pid: Int32) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try Self.postMouseEvent(type: .mouseMoved, at: start, pid: pid)
            try await Task.sleep(for: .milliseconds(16))
            try Self.postMouseEvent(type: .leftMouseDown, at: start, pid: pid)

            var lastPoint = start
            do {
                for step in 1 ... 12 {
                    try Task.checkCancellation()
                    let progress = CGFloat(step) / 12
                    lastPoint = CGPoint(
                        x: start.x + (end.x - start.x) * progress,
                        y: start.y + (end.y - start.y) * progress
                    )
                    try Self.postMouseEvent(type: .leftMouseDragged, at: lastPoint, pid: pid)
                    try await Task.sleep(for: .milliseconds(12))
                }
                try Self.postMouseEvent(type: .leftMouseUp, at: end, pid: pid)
            } catch {
                try? Self.postMouseEvent(type: .leftMouseUp, at: lastPoint, pid: pid)
                throw error
            }
        }
    }

    func scroll(
        at point: CGPoint,
        direction: ComputerUseScrollDirection,
        pages: Double,
        pid: Int32
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
                wheel1: Int32(clamping: Int(delta.vertical.rounded())),
                wheel2: Int32(clamping: Int(delta.horizontal.rounded())),
                wheel3: 0
            ) else {
                throw ComputerUseActionError.eventCreationFailed
            }
            scroll.location = point
            move.postToPid(pid)
            scroll.postToPid(pid)
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
        pid: Int32
    ) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ComputerUseActionError.eventCreationFailed
        }
        event.postToPid(pid)
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
