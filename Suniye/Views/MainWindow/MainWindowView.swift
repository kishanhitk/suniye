import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var selection: MainWindowSection = MainWindowSection.initialSelection(arguments: CommandLine.arguments)
    @State private var vocabularyDraft = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(MainWindowPalette.divider)
                .frame(width: 1)
            detail
        }
        .background(MainWindowPalette.windowBackground)
        .onAppear {
            logRenderedSection()
        }
        .onChange(of: selection) { _, _ in
            logRenderedSection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text("Suniye")
                    .font(AppTypography.appTitle)
                    .foregroundStyle(MainWindowPalette.sidebarTitle)
            }
            .padding(.top, AppMetrics.sidebarBrandTop)
            .padding(.horizontal, AppMetrics.sidebarBrandHorizontal)
            .padding(.bottom, AppMetrics.sidebarBrandBottom)

            VStack(alignment: .leading, spacing: AppMetrics.sidebarRowSpacing) {
                ForEach(MainWindowSection.allCases, id: \.self) { section in
                    SidebarNavigationRow(
                        section: section,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                    .accessibilityIdentifier(section.accessibilityIdentifier)
                }
            }
            .padding(.horizontal, AppMetrics.sidebarPaddingHorizontal)

            Spacer(minLength: 0)
        }
        .frame(width: AppMetrics.sidebarWidth)
        .background(MainWindowPalette.sidebarBackground)
    }

    private var detail: some View {
        Group {
            switch selection {
            case .dashboard:
                DashboardPage(appState: appState) { selection = $0 }
            case .history:
                HistoryPage(appState: appState)
            case .hotkey:
                HotkeyPage(appState: appState)
            case .model:
                ModelPage(appState: appState)
            case .vocabulary:
                VocabularyPage(appState: appState, draft: $vocabularyDraft)
            case .llm:
                LLMPage(appState: appState)
            case .general:
                GeneralPage(appState: appState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func logRenderedSection() {
        AppLogger.shared.log(.info, "main window section rendered section=\(selection.rawValue)")
    }
}
