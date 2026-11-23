import Foundation

extension SettingsRowID {
    /// Whether the app shows this row right now. Search lists no row that
    /// opening would not find.
    @MainActor
    func isAvailable(in appState: AppState) -> Bool {
        switch self {
        case .microphonePermission:
            return !appState.hasMicPermission
        case .accessibilityPermission:
            return !appState.hasAccessibilityPermission
        case .modelStatus:
            return !appState.isSelectedModelCurrent
        case .revealModelInFinder:
            return appState.asrModelSecondaryActionsEnabled(for: appState.currentASRModelEntry.id)
        case .magicFormatEngine, .baseInstructions, .appSpecificWritingStyle, .vocabulary, .keepLearning:
            return appState.llmEnabled
        case .keepAlive:
            return appState.llmEnabled && appState.usesLocalGemmaMagicFormatSettings
        case .updateChannel, .checkAutomatically:
            return appState.updatesEnabled
        default:
            return true
        }
    }

    /// Whether search lists the row. While Magic Format is off its rows stay
    /// listed: the page still names them, and opening one shows the page with
    /// its switch.
    @MainActor
    func isSearchable(in appState: AppState) -> Bool {
        isAvailable(in: appState) || (place == .magicFormat && !appState.llmEnabled)
    }

    /// The row a search result opens: the row itself, or the Magic Format
    /// switch while Magic Format is off.
    @MainActor
    func searchTarget(in appState: AppState) -> SettingsRowID {
        isAvailable(in: appState) ? self : .magicFormat
    }

    /// Whether the row's control can change anything. Live preview needs a
    /// model that writes text while you speak. The Never ask for sheet can only
    /// remove apps, which the call card adds.
    @MainActor
    func isEnabled(in appState: AppState) -> Bool {
        switch self {
        case .liveTranscriptionPreview:
            return appState.currentASRModelEntry.family.supportsLivePreview
        case .neverAskFor:
            return !appState.meetings.settings.neverAskBundleIDs.isEmpty
        default:
            return true
        }
    }

    /// The hint the row shows right now. The row and search both read it, so a
    /// row is found by what its hint says.
    @MainActor
    func currentInfo(in appState: AppState) -> String? {
        switch self {
        case .inputDevice:
            return appState.microphone.inputDeviceInfoText
        case .accessibilityPermission:
            return appState.accessibilityGrantLikelyStale ? appState.staleAccessibilityGrantInstruction : info
        case .updateChannel:
            return appState.updateChannel.detail
        case .version:
            return appState.updatesEnabled ? info : "Updates are off in this build."
        case .liveTranscriptionPreview:
            return isEnabled(in: appState) ? info : "Not available with \(appState.currentASRModelEntry.displayName)."
        case .meetingFiles:
            guard let days = appState.meetings.settings.audioRetention.days else {
                return "Audio is deleted when the transcript is ready."
            }
            return "Audio is deleted \(days) days after the meeting."
        default:
            return info
        }
    }
}
