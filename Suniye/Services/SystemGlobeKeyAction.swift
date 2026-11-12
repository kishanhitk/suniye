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
    static func current() -> SystemGlobeKeyAction {
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(domain)
        switch CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, domain) as? Int {
        case 0:
            return .doNothing
        case 1:
            return .changeInputSource
        case 3:
            return .startDictation
        default:
            return .showEmojiAndSymbols
        }
    }
}
