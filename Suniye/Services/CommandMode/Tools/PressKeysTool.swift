import CoreGraphics

/// Synthesizes a keyboard shortcut like "cmd+t" or "shift+cmd+4".
protocol KeyChordPosting {
    func post(keyCode: CGKeyCode, flags: CGEventFlags)
}

struct SystemKeyChordPoster: KeyChordPosting {
    func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

struct PressKeysTool: AgentTool {
    let name = "press_keys"
    let risk: RiskTier = .risky
    let poster: KeyChordPosting

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let chord = (arguments["keys"] ?? arguments["chord"])?.trimmingCharacters(in: .whitespaces), !chord.isEmpty else {
            throw CommandModeError.malformedToolCall("press_keys needs 'keys'")
        }
        guard let parsed = KeyChord.parse(chord) else {
            return ToolResult(output: "unrecognized keys: \(chord)", isTerminal: false)
        }
        poster.post(keyCode: parsed.keyCode, flags: parsed.flags)
        return ToolResult(output: "pressed \(chord)", isTerminal: false)
    }
}

/// Pure chord parsing (unit-testable): "cmd+shift+t" → virtual key code + modifier
/// flags. Returns nil when the base key isn't recognized.
enum KeyChord {
    static func parse(_ chord: String) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        let parts = chord.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let base = parts.last, !base.isEmpty else { return nil }
        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: return nil
            }
        }
        guard let code = keyCode(for: base) else { return nil }
        return (code, flags)
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        if let named = named[key] { return named }
        if key.count == 1, let single = singleChar[Character(key)] { return single }
        return nil
    }

    private static let singleChar: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]

    private static let named: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, " ": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "comma": 43, "period": 47, "slash": 44, "minus": 27, "equal": 24,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}
