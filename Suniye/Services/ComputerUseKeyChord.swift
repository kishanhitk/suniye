import CoreGraphics
import Foundation

struct ComputerUseParsedKeyChord: Equatable, Sendable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

enum ComputerUseKeyChord {
    static func parse(_ value: String) throws -> ComputerUseParsedKeyChord {
        let parts = value.split(separator: "+", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }), let keyName = parts.last else {
            throw ComputerUseActionError.unsupportedKey(value)
        }

        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            guard let flag = modifierFlag(modifier) else {
                throw ComputerUseActionError.unsupportedKey(modifier)
            }
            flags.insert(flag)
        }
        guard let keyCode = keyCode(keyName) else {
            throw ComputerUseActionError.unsupportedKey(keyName)
        }
        return ComputerUseParsedKeyChord(keyCode: keyCode, flags: flags)
    }

    private static func modifierFlag(_ value: String) -> CGEventFlags? {
        return switch normalized(value) {
        case "control", "ctrl", "control_l", "control_r":
            .maskControl
        case "alt", "option", "alt_l", "alt_r", "option_l", "option_r":
            .maskAlternate
        case "shift", "shift_l", "shift_r":
            .maskShift
        case "super", "command", "cmd", "meta", "super_l", "super_r", "command_l", "command_r":
            .maskCommand
        default:
            nil
        }
    }

    private static func keyCode(_ value: String) -> CGKeyCode? {
        if value.count == 1 {
            return TextInsertionService.virtualKeyCode(for: value.lowercased())
        }
        return switch normalized(value) {
        case "return", "enter": 36
        case "tab": 48
        case "space": 49
        case "backspace", "delete": 51
        case "escape", "esc": 53
        case "command", "cmd", "meta", "super", "command_l", "super_l": 55
        case "shift", "shift_l": 56
        case "caps_lock": 57
        case "option", "alt", "option_l", "alt_l": 58
        case "control", "ctrl", "control_l": 59
        case "shift_r": 60
        case "option_r", "alt_r": 61
        case "control_r": 62
        case "super_r", "command_r": 54
        case "f17": 64
        case "kp_decimal", "numpad_decimal": 65
        case "kp_multiply", "numpad_multiply": 67
        case "kp_add", "numpad_add": 69
        case "num_lock", "clear": 71
        case "volume_up": 72
        case "volume_down": 73
        case "mute": 74
        case "kp_divide", "numpad_divide": 75
        case "kp_enter", "numpad_enter": 76
        case "kp_subtract", "numpad_subtract": 78
        case "f18": 79
        case "f19": 80
        case "kp_equal", "numpad_equal": 81
        case "kp_0", "kp0", "numpad0": 82
        case "kp_1", "kp1", "numpad1": 83
        case "kp_2", "kp2", "numpad2": 84
        case "kp_3", "kp3", "numpad3": 85
        case "kp_4", "kp4", "numpad4": 86
        case "kp_5", "kp5", "numpad5": 87
        case "kp_6", "kp6", "numpad6": 88
        case "kp_7", "kp7", "numpad7": 89
        case "f20": 90
        case "kp_8", "kp8", "numpad8": 91
        case "kp_9", "kp9", "numpad9": 92
        case "f5": 96
        case "f6": 97
        case "f7": 98
        case "f3": 99
        case "f8": 100
        case "f9": 101
        case "f11": 103
        case "f13": 105
        case "f16": 106
        case "f14": 107
        case "f10": 109
        case "f12": 111
        case "f15": 113
        case "help", "insert": 114
        case "home": 115
        case "page_up", "prior": 116
        case "forward_delete", "delete_forward": 117
        case "f4": 118
        case "end": 119
        case "f2": 120
        case "page_down", "next": 121
        case "f1": 122
        case "left", "arrow_left": 123
        case "right", "arrow_right": 124
        case "down", "arrow_down": 125
        case "up", "arrow_up": 126
        default:
            TextInsertionService.virtualKeyCode(for: punctuation(value))
        }
    }

    private static func punctuation(_ value: String) -> String {
        switch normalized(value) {
        case "period", "dot": "."
        case "comma": ","
        case "slash": "/"
        case "backslash": "\\"
        case "semicolon": ";"
        case "apostrophe", "quote": "'"
        case "bracketleft", "left_bracket": "["
        case "bracketright", "right_bracket": "]"
        case "minus", "hyphen": "-"
        case "equal", "equals": "="
        case "grave", "backquote", "backtick": String(UnicodeScalar(96))
        default: value
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
