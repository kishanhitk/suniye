import Foundation

/// Where a settings row lives.
enum SettingsPlace: Equatable {
    case pane(SettingsPane)
    case magicFormat

    var title: String {
        switch self {
        case let .pane(pane):
            return pane.title
        case .magicFormat:
            return MainWindowSection.style.title
        }
    }

    var icon: String {
        switch self {
        case let .pane(pane):
            return pane.icon
        case .magicFormat:
            return MainWindowSection.style.icon
        }
    }
}

/// Every row that settings search can find. The rows take their title and
/// hint from here, so a result always names what the pane shows.
enum SettingsRowID: String, CaseIterable, Hashable {
    case microphonePermission
    case accessibilityPermission
    case inputDevice
    case echoCancellation
    case soundFeedback
    case holdToDictate
    case pasteLastTranscript
    case holdToEditSelection
    case pressEnterAfterPasting
    case liveTranscriptionPreview
    case hideWhileIdle
    case showMeetingTime
    case indicatorPosition
    case speechModel
    case modelLanguages
    case modelSpeed
    case modelOnDisk
    case modelStatus
    case revealModelInFinder
    case whenACallStarts
    case neverAskFor
    case transcriptModel
    case summaryModel
    case defaultTemplate
    case summaryTemplates
    case keepMeetingAudio
    case meetingFiles
    case theme
    case launchAtLogin
    case shareAnonymousAnalytics
    case whatWeCollect
    case version
    case updateChannel
    case checkAutomatically
    case reportAProblem
    case magicFormat
    case magicFormatEngine
    case keepAlive
    case baseInstructions
    case appSpecificWritingStyle
    case vocabulary
    case keepLearning

    var title: String {
        switch self {
        case .microphonePermission:
            return "Microphone"
        case .accessibilityPermission:
            return "Accessibility"
        case .inputDevice:
            return "Input device"
        case .echoCancellation:
            return "Echo cancellation"
        case .soundFeedback:
            return "Sound feedback"
        case .holdToDictate:
            return "Hold to dictate"
        case .pasteLastTranscript:
            return "Paste last transcript"
        case .holdToEditSelection:
            return "Hold to edit selection"
        case .pressEnterAfterPasting:
            return "Press Return after pasting"
        case .liveTranscriptionPreview:
            return "Live transcription preview"
        case .hideWhileIdle:
            return "Hide while idle"
        case .showMeetingTime:
            return "Show meeting time"
        case .indicatorPosition:
            return "Position"
        case .speechModel:
            return "Model"
        case .modelLanguages:
            return "Languages"
        case .modelSpeed:
            return "Speed"
        case .modelOnDisk:
            return "On disk"
        case .modelStatus:
            return "Status"
        case .revealModelInFinder:
            return "Reveal in Finder"
        case .whenACallStarts:
            return "When a call starts"
        case .neverAskFor:
            return "Never ask for"
        case .transcriptModel:
            return "Transcript model"
        case .summaryModel:
            return "Summary model"
        case .defaultTemplate:
            return "Default template"
        case .summaryTemplates:
            return "Summary templates"
        case .keepMeetingAudio:
            return "Keep meeting audio"
        case .meetingFiles:
            return "Meeting files"
        case .theme:
            return "Theme"
        case .launchAtLogin:
            return "Launch at login"
        case .shareAnonymousAnalytics:
            return "Share anonymous analytics"
        case .whatWeCollect:
            return "What we collect"
        case .version:
            return "Version"
        case .updateChannel:
            return "Update channel"
        case .checkAutomatically:
            return "Check automatically"
        case .reportAProblem:
            return "Report a problem"
        case .magicFormat:
            return "Magic Format"
        case .magicFormatEngine:
            return "Engine"
        case .keepAlive:
            return "Keep alive"
        case .baseInstructions:
            return "Base instructions"
        case .appSpecificWritingStyle:
            return "App-specific writing style"
        case .vocabulary:
            return "Vocabulary"
        case .keepLearning:
            return "Keep learning from my corrections"
        }
    }

    /// The hint behind the row's info mark. A row whose hint depends on state
    /// has none here; `currentInfo(in:)` gives the hint it shows.
    var info: String? {
        switch self {
        case .microphonePermission:
            return "Required to capture dictation audio."
        case .accessibilityPermission:
            return "Required to paste transcribed text into other apps."
        case .echoCancellation:
            return "Uses Apple's Voice Processing when the current input and output route supports it. It is bypassed for Bluetooth routes."
        case .holdToDictate:
            return "Hold the shortcut and speak. To dictate hands-free, double-tap it, then press it again to finish. Esc cancels until you type or click in another app."
        case .pasteLastTranscript:
            return "Focus a text field and press this shortcut to insert your latest completed dictation without submitting it again."
        case .holdToEditSelection:
            return "Select text in any app, hold the shortcut, and speak an instruction like \"make this formal\". With nothing selected, the spoken instruction generates text at the cursor. Requires Magic Format."
        case .hideWhileIdle:
            return "Hide the floating indicator when \(AppIdentity.current.displayName) is ready but not actively dictating. When hidden, floating click-to-start is unavailable until the indicator appears again for recording, processing, or errors."
        case .indicatorPosition:
            return "Drag the floating indicator to place it somewhere that stays out of the way."
        case .whenACallStarts:
            return "\(AppIdentity.current.displayName) notices when a call app starts a call."
        case .transcriptModel:
            return "Writes the transcript after the recording stops. Dictation keeps its own model."
        case .summaryModel:
            return "Writes the summary after the transcript. ChatGPT and API endpoint send the transcript and your notes to that service."
        case .keepMeetingAudio:
            return "Audio lets you play back and transcribe a meeting again. Transcripts and notes stay until you delete them. A change applies the next time \(AppIdentity.current.displayName) opens or finishes a transcript."
        case .keepAlive:
            return "Shorter frees memory sooner; the next dictation then waits for the model to load again."
        case .vocabulary:
            return "Words the formatter is told to spell your way."
        case .inputDevice, .soundFeedback, .pressEnterAfterPasting, .liveTranscriptionPreview, .showMeetingTime,
             .speechModel, .modelLanguages, .modelSpeed, .modelOnDisk, .modelStatus, .revealModelInFinder,
             .neverAskFor, .defaultTemplate, .summaryTemplates, .meetingFiles, .theme,
             .launchAtLogin, .shareAnonymousAnalytics, .whatWeCollect, .version, .updateChannel,
             .checkAutomatically, .reportAProblem, .magicFormat, .magicFormatEngine, .baseInstructions,
             .appSpecificWritingStyle, .keepLearning:
            return nil
        }
    }

    /// Words people use for this row that its title does not contain.
    var aliases: [String] {
        switch self {
        case .microphonePermission:
            return ["permission", "access", "grant", "privacy"]
        case .accessibilityPermission:
            return ["permission", "access", "grant", "paste"]
        case .inputDevice:
            return ["microphone", "mic", "audio device", "input", "headset", "airpods"]
        case .echoCancellation:
            return ["echo", "noise", "voice processing"]
        case .soundFeedback:
            return ["sounds", "beep", "chime", "audio cue"]
        case .holdToDictate:
            return ["shortcut", "hotkey", "push to talk", "keybind", "key", "hands-free", "globe", "fn"]
        case .pasteLastTranscript:
            return ["shortcut", "hotkey", "keybind", "key", "insert"]
        case .holdToEditSelection:
            return ["shortcut", "hotkey", "keybind", "key", "rewrite", "command"]
        case .pressEnterAfterPasting:
            return ["enter", "submit", "send", "auto submit"]
        case .liveTranscriptionPreview:
            return ["indicator", "overlay", "pill", "popup", "live text"]
        case .hideWhileIdle:
            return ["indicator", "overlay", "pill", "popup", "floating"]
        case .showMeetingTime:
            return ["indicator", "pill", "timer", "clock"]
        case .indicatorPosition:
            return ["indicator", "overlay", "pill", "move", "reset"]
        case .speechModel:
            return ["speech model", "transcription", "engine", "asr", "stt", "provider"] + Self.speechModelNames
        case .modelLanguages:
            return ["multilingual", "dialects"]
        case .modelSpeed:
            return ["fast", "slow", "latency", "performance"]
        case .modelOnDisk:
            return ["disk", "storage", "size", "space", "delete"]
        case .modelStatus:
            return ["download", "install", "missing"]
        case .revealModelInFinder:
            return ["folder", "files", "location"]
        case .whenACallStarts:
            return ["call", "auto record", "record automatically", "zoom", "teams", "detect"]
        case .neverAskFor:
            return ["apps", "exclude", "ignore", "block"]
        case .transcriptModel:
            return ["meeting transcript", "asr", "transcription"] + Self.speechModelNames
        case .summaryModel:
            return ["ai", "llm", "chatgpt", "api", "openai"]
        case .defaultTemplate:
            return ["summary", "notes"]
        case .summaryTemplates:
            return ["notes", "format"]
        case .keepMeetingAudio:
            return ["history", "recordings", "retention", "auto-delete", "storage", "delete"]
        case .meetingFiles:
            return ["recordings", "storage", "disk", "folder", "finder"]
        case .theme:
            return ["appearance", "dark mode", "light mode", "dark", "light", "color scheme", "night"]
        case .launchAtLogin:
            return ["startup", "login", "autostart", "open at login", "boot"]
        case .shareAnonymousAnalytics:
            return ["telemetry", "tracking", "privacy", "data"]
        case .whatWeCollect:
            return ["privacy", "data", "analytics", "telemetry"]
        case .version:
            return ["update", "check for updates", "about", "release"]
        case .updateChannel:
            return ["update", "beta", "preview", "stable", "release"]
        case .checkAutomatically:
            return ["update", "auto update", "automatic"]
        case .reportAProblem:
            return ["bug", "feedback", "support", "issue", "help", "contact"]
        case .magicFormat:
            return ["prompt", "cleanup", "post-processing", "enhancement", "llm", "ai", "formatting", "grammar", "punctuation"]
        case .magicFormatEngine:
            // The row's title is the engine in use, so every engine name finds it.
            return [
                "local model", "apple intelligence", "your own api endpoint", "api endpoint", "automatic",
                "model", "llm", "ai", "provider", "gemma", "openrouter", "api key",
            ]
        case .keepAlive:
            return ["memory", "ram", "unload", "model"]
        case .baseInstructions:
            return ["prompt", "system prompt", "rules"]
        case .appSpecificWritingStyle:
            return ["per app", "apps", "tone", "prompt", "slack", "mail"]
        case .vocabulary:
            return ["dictionary", "replacements", "custom words", "spelling", "words", "names", "terms"]
        case .keepLearning:
            return ["learn", "auto learn", "vocabulary"]
        }
    }

    /// The name of every speech model, as the panes show it, so a name on
    /// screen finds its row.
    private static let speechModelNames = ASRModelID.allCases.map { ASRModelCatalog.entry(for: $0).displayName }

    var place: SettingsPlace {
        switch self {
        case .microphonePermission, .accessibilityPermission:
            return .pane(.permissions)
        case .inputDevice, .echoCancellation, .soundFeedback:
            return .pane(.microphone)
        case .holdToDictate, .pasteLastTranscript, .holdToEditSelection, .pressEnterAfterPasting:
            return .pane(.shortcuts)
        case .liveTranscriptionPreview, .hideWhileIdle, .showMeetingTime, .indicatorPosition:
            return .pane(.indicator)
        case .speechModel, .modelLanguages, .modelSpeed, .modelOnDisk, .modelStatus, .revealModelInFinder:
            return .pane(.speechModel)
        case .whenACallStarts, .neverAskFor, .transcriptModel, .summaryModel, .defaultTemplate, .summaryTemplates,
             .keepMeetingAudio, .meetingFiles:
            return .pane(.meetings)
        case .theme, .launchAtLogin, .shareAnonymousAnalytics, .whatWeCollect, .version, .updateChannel,
             .checkAutomatically, .reportAProblem:
            return .pane(.general)
        case .magicFormat, .magicFormatEngine, .keepAlive, .baseInstructions, .appSpecificWritingStyle,
             .vocabulary, .keepLearning:
            return .magicFormat
        }
    }
}

enum SettingsSearch {
    /// Rows that match every word of the query, best first. A word matches the
    /// start of a word in the title, an alias or the place name, or any part of
    /// the hint once it has three letters. Ties keep catalog order. `info` gives
    /// the hint each row shows right now.
    static func results(
        for query: String,
        in rows: [SettingsRowID],
        info: (SettingsRowID) -> String?
    ) -> [SettingsRowID] {
        let tokens = words(in: query)
        guard !tokens.isEmpty else {
            return []
        }

        var matches: [(row: SettingsRowID, points: Int, index: Int)] = []
        for (index, row) in rows.enumerated() {
            if let points = score(row, hint: info(row) ?? "", tokens: tokens) {
                matches.append((row: row, points: points, index: index))
            }
        }
        matches.sort { lhs, rhs in
            lhs.points == rhs.points ? lhs.index < rhs.index : lhs.points > rhs.points
        }
        return matches.map(\.row)
    }

    /// The title with the part that each query word matched in bold.
    static func emphasized(_ title: String, query: String) -> AttributedString {
        var result = AttributedString(title)
        let tokens = words(in: query)
        var offset = 0

        for word in title.split(omittingEmptySubsequences: false, whereSeparator: isSeparator) {
            let folded = normalized(String(word))
            if let length = tokens.filter({ folded.hasPrefix($0) }).map(\.count).max() {
                let start = result.characters.index(result.startIndex, offsetBy: offset)
                let end = result.characters.index(start, offsetBy: min(length, word.count))
                result[start..<end].inlinePresentationIntent = .stronglyEmphasized
            }
            offset += word.count + 1
        }
        return result
    }

    private static func score(_ row: SettingsRowID, hint: String, tokens: [String]) -> Int? {
        let title = words(in: row.title)
        let aliases = row.aliases.flatMap(words(in:))
        let place = words(in: row.place.title)
        let info = normalized(hint)

        var total = 0
        for token in tokens {
            if title.contains(where: { $0.hasPrefix(token) }) {
                total += 3
            } else if aliases.contains(where: { $0.hasPrefix(token) }) {
                total += 2
            } else if place.contains(where: { $0.hasPrefix(token) }) {
                total += 1
            } else if token.count >= 3, info.contains(token) {
                total += 1
            } else {
                return nil
            }
        }
        return total
    }

    private static func words(in text: String) -> [String] {
        normalized(text).split(whereSeparator: isSeparator).map(String.init)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func isSeparator(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber
    }
}
