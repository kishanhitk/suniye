import Foundation

/// The dot or status at the end of a sidebar row. A dot means something stops
/// a feature from working, the same problems the Transcripts page lists;
/// notices that change nothing (a Bluetooth microphone, the Globe key setting)
/// stay inside their pane.
extension MainWindowSection {
    @MainActor
    func sidebarAccessory(_ appState: AppState) -> SidebarRowAccessory? {
        switch self {
        case .meetings:
            return appState.meetings.live.map { .recording($0.isPaused ? .paused : .recording) }
        case .style:
            if let progress = appState.localGemmaInstallProgress {
                return .status(percentText(progress))
            }
            return appState.hasAttention(at: .section(.style)) ? .attention : nil
        case .settings:
            let panes = SettingsPane.listed(permissionsMissing: !appState.hasMicPermission || !appState.hasAccessibilityPermission)
            return panes.contains { $0.sidebarAccessory(appState) == .attention } ? .attention : nil
        case .dashboard:
            return nil
        }
    }
}

extension SettingsPane {
    @MainActor
    func sidebarAccessory(_ appState: AppState) -> SidebarRowAccessory? {
        switch self {
        case .permissions:
            return .attention
        case .microphone:
            return appState.microphone.hasNoInput ? .attention : nil
        case .shortcuts:
            return appState.hotkeyValidationMessage == nil ? nil : .attention
        case .speechModel:
            if appState.phase == .downloadingModel {
                return .status(percentText(appState.downloadProgress))
            }
            return appState.hasAttention(at: .settings(.speechModel)) ? .attention : nil
        case .general:
            // The switch shows on while macOS holds the login item for
            // approval, but the app does not open at login until then.
            let loginItemBlocked = appState.launchAtLoginError != nil || appState.launchAtLoginStatus == .requiresApproval
            return loginItemBlocked ? .attention : nil
        case .indicator, .meetings:
            return nil
        }
    }
}

private func percentText(_ progress: Double) -> String {
    "\(Int(progress * 100))%"
}

extension AppState {
    /// Whether a problem on the Transcripts page points at this place.
    func hasAttention(at destination: MainWindowDestination) -> Bool {
        attentionItems.contains { $0.recommendedDestination == destination }
    }
}
