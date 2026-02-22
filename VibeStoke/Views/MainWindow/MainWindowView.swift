import SwiftUI

enum MainWindowSection: String, CaseIterable, Hashable {
    case stats
    case settings
    case about

    var title: String {
        switch self {
        case .stats:
            return "Stats"
        case .settings:
            return "Settings"
        case .about:
            return "About"
        }
    }

    var icon: String {
        switch self {
        case .stats:
            return "chart.bar"
        case .settings:
            return "gearshape"
        case .about:
            return "info.circle"
        }
    }
}

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var selection: MainWindowSection = CommandLine.arguments.contains("--open-settings") ? .settings : .stats

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(selection.title)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .stats:
            StatsDetailView(
                appState: appState,
                onOpenSettings: { selection = .settings }
            )
        case .settings:
            SettingsDetailView(appState: appState)
        case .about:
            AboutDetailView(appState: appState)
        }
    }
}
