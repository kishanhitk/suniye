import Foundation

/// The macOS Keyboard setting "Press 🌐 key to". Any action other than Do
/// Nothing also runs on each Globe tap, so a Globe double tap or a finishing
/// tap would open Emoji & Symbols, change the input source, or start macOS
/// Dictation as well.
enum SystemGlobeKeyAction: Equatable {
    case doNothing
    case changeInputSource
    case showEmojiAndSymbols
    case startDictation

    /// Apple does not document the key. With no value, System Settings on
    /// macOS 27.2 shows Show Emoji & Symbols.
    init(fnUsageType: Int?) {
        switch fnUsageType {
        case 0:
            self = .doNothing
        case 1:
            self = .changeInputSource
        case 3:
            self = .startDictation
        default:
            // 2, no value, or a value this version does not know.
            self = .showEmojiAndSymbols
        }
    }

    static func current() -> SystemGlobeKeyAction {
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(domain)
        return SystemGlobeKeyAction(fnUsageType: CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, domain) as? Int)
    }
}
