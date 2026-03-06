import AppKit
import Foundation

struct HistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let durationSeconds: TimeInterval
    let wordCount: Int
    let text: String
    let submitted: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        durationSeconds: TimeInterval,
        wordCount: Int,
        text: String,
        submitted: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.text = text
        self.submitted = submitted
    }
}

struct StatsSnapshot: Codable, Equatable {
    var sessionCount: Int
    var wordsTranscribed: Int
    var totalDictationSeconds: TimeInterval

    static let zero = StatsSnapshot(sessionCount: 0, wordsTranscribed: 0, totalDictationSeconds: 0)

    mutating func applyAddedEntry(_ entry: HistoryEntry) {
        sessionCount += 1
        wordsTranscribed += entry.wordCount
        totalDictationSeconds += entry.durationSeconds
    }

    mutating func applyRemovedEntry(_ entry: HistoryEntry) {
        sessionCount = max(0, sessionCount - 1)
        wordsTranscribed = max(0, wordsTranscribed - entry.wordCount)
        totalDictationSeconds = max(0, totalDictationSeconds - entry.durationSeconds)
    }
}

struct HotkeyShortcut: Codable, Equatable {
    struct Modifiers: OptionSet, Codable, Equatable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)
        static let function = Modifiers(rawValue: 1 << 4)

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        var eventFlags: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if contains(.command) { flags.insert(.command) }
            if contains(.option) { flags.insert(.option) }
            if contains(.control) { flags.insert(.control) }
            if contains(.shift) { flags.insert(.shift) }
            if contains(.function) { flags.insert(.function) }
            return flags
        }

        static func from(_ flags: NSEvent.ModifierFlags) -> Modifiers {
            let normalized = flags.intersection(.deviceIndependentFlagsMask)
            var value: Modifiers = []
            if normalized.contains(.command) { value.insert(.command) }
            if normalized.contains(.option) { value.insert(.option) }
            if normalized.contains(.control) { value.insert(.control) }
            if normalized.contains(.shift) { value.insert(.shift) }
            if normalized.contains(.function) { value.insert(.function) }
            return value
        }

        var displayText: String {
            var parts: [String] = []
            if contains(.control) { parts.append("Control") }
            if contains(.option) { parts.append("Option") }
            if contains(.shift) { parts.append("Shift") }
            if contains(.command) { parts.append("Command") }
            if contains(.function) { parts.append("Fn") }
            return parts.joined(separator: " + ")
        }
    }

    var keyCode: UInt16?
    var modifiers: Modifiers

    static let defaultHoldToTalk = HotkeyShortcut(keyCode: nil, modifiers: [.function])

    var isEmpty: Bool {
        keyCode == nil && modifiers.isEmpty
    }

    var displayText: String {
        let modifierText = modifiers.displayText
        guard let keyCode else {
            return modifierText.isEmpty ? "Unassigned" : modifierText
        }

        let keyText = Self.keyName(for: keyCode)
        if modifierText.isEmpty {
            return keyText
        }
        return "\(modifierText) + \(keyText)"
    }

    func matches(modifiers currentModifiers: Modifiers, pressedKeys: Set<UInt16>) -> Bool {
        guard currentModifiers == modifiers else {
            return false
        }

        guard let keyCode else {
            return !modifiers.isEmpty
        }

        return pressedKeys.contains(keyCode)
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return "Key \(keyCode)"
        }
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }
}

struct AppPreferences: Codable, Equatable {
    var hotkeyShortcut: HotkeyShortcut
    var selectedInputDeviceUID: String?
    var launchAtLoginEnabled: Bool

    init(
        hotkeyShortcut: HotkeyShortcut = .defaultHoldToTalk,
        selectedInputDeviceUID: String? = nil,
        launchAtLoginEnabled: Bool = false
    ) {
        self.hotkeyShortcut = hotkeyShortcut
        self.selectedInputDeviceUID = selectedInputDeviceUID
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}

struct AudioInputDevice: Codable, Equatable, Identifiable {
    var id: String { uid }
    let uid: String
    let name: String
    let isDefault: Bool
}

struct ModelFileStatus: Identifiable, Equatable {
    var id: String { fileName }
    let fileName: String
    let exists: Bool
    let sizeBytes: Int64
}

struct ModelDiagnostics: Equatable {
    let modelDirectoryPath: String
    let requiredFiles: [ModelFileStatus]
    let diskUsageBytes: Int64
    let isReady: Bool
}
