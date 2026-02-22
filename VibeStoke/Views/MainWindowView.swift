import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var selection: MainWindowSection = CommandLine.arguments.contains("--open-settings") ? .general : .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState, selection: $selection)
        } detail: {
            switch selection {
            case .dashboard:
                DashboardPageView(appState: appState)
            case .history:
                HistoryPageView(appState: appState)
            case .hotkey:
                HotkeySettingsPageView(appState: appState)
            case .model:
                ModelPageView(appState: appState)
            case .vocabulary:
                VocabularyPageView(appState: appState)
            case .llmPolish:
                LLMPolishPageView(appState: appState)
            case .general:
                GeneralPageView(appState: appState)
            }
        }
    }
}
