import Foundation
import SuniyeAnalytics

/// Maps a frontmost app bundle id to a coarse category. The raw bundle id is
/// never sent (it would be a usage fingerprint) — only the category.
enum TargetCategoryMapper {
    static func category(for bundleID: String?) -> TargetCategory {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return .other }
        func has(_ needles: String...) -> Bool { needles.contains { id.contains($0) } }

        if has("mail", "outlook", "spark", "airmail", "sparrow", "canary") { return .email }
        // Terminal before IDE: "com.googlecode.iterm2" contains "code".
        if has("terminal", "iterm", "warp", "ghostty", "alacritty", "kitty", "hyper") { return .terminal }
        if has("xcode", "vscode", "vscodium", "jetbrains", "intellij", "pycharm", "sublimetext", "nova", "zed", "cursor") { return .ide }
        if has("safari", "chrome", "firefox", "arc", "edge", "brave", "vivaldi", "orion") { return .browser }
        if has("slack", "discord", "messages", "telegram", "whatsapp", "signal", "teams", "zoom") { return .chat }
        if has("notes", "notion", "obsidian", "bear", "craft", "logseq", "roam") { return .notes }
        if has("word", "pages", "keynote", "powerpoint", "excel", "numbers", "docs") { return .office }
        if has("textedit", "editor", "ia.writer", "iawriter", "ulysses") { return .editor }
        return .other
    }
}

/// Computer Use analytics vocabulary mapping, owned by the feature so the
/// eval runner links it without the app-wide analytics surface.
enum ComputerUseAnalyticsMapping {
    static func computerUseOutcome(_ outcome: ComputerUseAgentOutcome) -> ComputerUseOutcome {
        switch outcome {
        case .completed: return .completed
        case .cancelled: return .cancelled
        case .failed: return .failed
        }
    }

    static func computerUseTool(_ name: ComputerUseToolName) -> ComputerUseTool {
        switch name {
        case .listApps: return .listApps
        case .getAppState: return .getAppState
        case .click: return .click
        case .performSecondaryAction: return .performSecondaryAction
        case .setValue: return .setValue
        case .selectText: return .selectText
        case .scroll: return .scroll
        case .drag: return .drag
        case .pressKey: return .pressKey
        case .typeText: return .typeText
        case .setVoiceActivation: return .setVoiceActivation
        // The outer code-mode tool is never recorded as a leaf tool; the sky
        // calls inside a script record as their concrete tools.
        case .nodeRepl: return .unknown
        }
    }

    /// Maps a tool failure to a closed reason vocabulary. The associated values
    /// of these errors carry app names and user text, so only the case is kept.
    static func computerUseFailureReason(_ error: Error) -> ComputerUseFailureReason {
        if let error = error as? ComputerUseActionError {
            switch error {
            case .observationRequired: return .observationRequired
            case .staleObservation: return .staleObservation
            case .elementUnavailable: return .elementUnavailable
            case .elementChanged: return .elementChanged
            case .elementDisabled: return .elementDisabled
            case .actionUnavailable: return .actionUnavailable
            case .textNotFound: return .textNotFound
            case .invalidArgument: return .invalidArgument
            default: return .unknown
            }
        }
        if error is ComputerUseRuntimeError {
            return .screenLocked
        }
        if error is ComputerUseModelToolCallError {
            return .decodeFailed
        }
        return .unknown
    }
}
