import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var selection: MainWindowSection = CommandLine.arguments.contains("--open-settings") ? .settings : .home
    @State private var isSidebarExpanded = true

    var body: some View {
        ZStack {
            AppTheme.windowBackground
                .ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarView(selection: $selection, isExpanded: isSidebarExpanded)
                    .frame(width: isSidebarExpanded ? 222 : 72)

                Group {
                    switch selection {
                    case .home:
                        DashboardPageView(appState: appState)
                    case .dictionary:
                        VocabularyPageView(appState: appState)
                    case .style:
                        LLMPolishPageView(appState: appState)
                    case .notes:
                        HistoryPageView(appState: appState)
                    case .settings:
                        SettingsPageView(appState: appState)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.panelCornerRadius, style: .continuous))
                .padding(.vertical, 10)
                .padding(.trailing, 10)
                .padding(.leading, 8)
            }
            .background(AppTheme.windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.windowCornerRadius, style: .continuous))
        }
        .animation(.easeInOut(duration: 0.18), value: isSidebarExpanded)
        .onReceive(NotificationCenter.default.publisher(for: .suniyeToggleSidebar)) { _ in
            isSidebarExpanded.toggle()
        }
        .environment(\.colorScheme, .light)
    }
}
