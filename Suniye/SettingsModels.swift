import AppKit
import Carbon
import Foundation

struct RecentResult: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let createdAt: Date
    let durationSeconds: TimeInterval
    let wasLLMPolished: Bool

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

struct AudioInputDevice: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let isDefault: Bool
}

struct HotkeyConfiguration: Codable, Equatable {
    enum Kind: String, Codable {
        case globe
        case keyCombo
    }

    var kind: Kind
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let globe = HotkeyConfiguration(kind: .globe, keyCode: UInt32(kVK_Function), carbonModifiers: 0)

    static func keyCombo(keyCode: UInt32, carbonModifiers: UInt32) -> HotkeyConfiguration {
        HotkeyConfiguration(kind: .keyCombo, keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    var displayString: String {
        switch kind {
        case .globe:
            return "Globe"
        case .keyCombo:
            let parts = modifierLabels + [Self.keyName(for: keyCode)]
            return parts.joined(separator: " + ")
        }
    }

    var exampleDescription: String {
        switch kind {
        case .globe:
            return "Fn/Globe key (macOS dictation key)"
        case .keyCombo:
            return displayString
        }
    }

    var modifierLabels: [String] {
        guard kind == .keyCombo else {
            return []
        }

        var labels: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 {
            labels.append("Control")
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            labels.append("Option")
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            labels.append("Shift")
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            labels.append("Command")
        }
        return labels
    }

    static func from(event: NSEvent) -> HotkeyConfiguration? {
        let modifiers = carbonModifiers(from: event.modifierFlags)

        if event.type == .flagsChanged,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .function {
            return .globe
        }

        guard event.type == .keyDown else {
            return nil
        }

        switch Int(event.keyCode) {
        case kVK_Command, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function:
            return nil
        default:
            return .keyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
        }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let mask = flags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0

        if mask.contains(.control) {
            carbon |= UInt32(controlKey)
        }
        if mask.contains(.option) {
            carbon |= UInt32(optionKey)
        }
        if mask.contains(.shift) {
            carbon |= UInt32(shiftKey)
        }
        if mask.contains(.command) {
            carbon |= UInt32(cmdKey)
        }

        return carbon
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Escape:
            return "Escape"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_ANSI_Grave:
            return "`"
        case kVK_ANSI_Comma:
            return ","
        case kVK_ANSI_Period:
            return "."
        case kVK_ANSI_Slash:
            return "/"
        case kVK_ANSI_Semicolon:
            return ";"
        case kVK_ANSI_Quote:
            return "'"
        case kVK_ANSI_LeftBracket:
            return "["
        case kVK_ANSI_RightBracket:
            return "]"
        case kVK_ANSI_Backslash:
            return "\\"
        case kVK_ANSI_Minus:
            return "-"
        case kVK_ANSI_Equal:
            return "="
        case kVK_ANSI_0:
            return "0"
        case kVK_ANSI_1:
            return "1"
        case kVK_ANSI_2:
            return "2"
        case kVK_ANSI_3:
            return "3"
        case kVK_ANSI_4:
            return "4"
        case kVK_ANSI_5:
            return "5"
        case kVK_ANSI_6:
            return "6"
        case kVK_ANSI_7:
            return "7"
        case kVK_ANSI_8:
            return "8"
        case kVK_ANSI_9:
            return "9"
        case kVK_ANSI_A:
            return "A"
        case kVK_ANSI_B:
            return "B"
        case kVK_ANSI_C:
            return "C"
        case kVK_ANSI_D:
            return "D"
        case kVK_ANSI_E:
            return "E"
        case kVK_ANSI_F:
            return "F"
        case kVK_ANSI_G:
            return "G"
        case kVK_ANSI_H:
            return "H"
        case kVK_ANSI_I:
            return "I"
        case kVK_ANSI_J:
            return "J"
        case kVK_ANSI_K:
            return "K"
        case kVK_ANSI_L:
            return "L"
        case kVK_ANSI_M:
            return "M"
        case kVK_ANSI_N:
            return "N"
        case kVK_ANSI_O:
            return "O"
        case kVK_ANSI_P:
            return "P"
        case kVK_ANSI_Q:
            return "Q"
        case kVK_ANSI_R:
            return "R"
        case kVK_ANSI_S:
            return "S"
        case kVK_ANSI_T:
            return "T"
        case kVK_ANSI_U:
            return "U"
        case kVK_ANSI_V:
            return "V"
        case kVK_ANSI_W:
            return "W"
        case kVK_ANSI_X:
            return "X"
        case kVK_ANSI_Y:
            return "Y"
        case kVK_ANSI_Z:
            return "Z"
        default:
            return "Key \(keyCode)"
        }
    }
}

struct GeneralSettings: Codable, Equatable {
    var preferredInputDeviceID: String?
    var autoSubmitEnabled: Bool = false
    var hotkeyConfiguration: HotkeyConfiguration = .globe
    var echoCancellationEnabled: Bool = false
    var hasSeenOnboardingWelcome: Bool? = nil
    var hasCompletedCoreOnboarding: Bool? = nil
}
