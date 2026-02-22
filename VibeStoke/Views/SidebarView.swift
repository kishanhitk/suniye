import SwiftUI

enum MainWindowSection: String, CaseIterable, Hashable {
    case dashboard
    case history
    case hotkey
    case model
    case vocabulary
    case llmPolish
    case general
}

struct SidebarView: View {
    @Bindable var appState: AppState
    @Binding var selection: MainWindowSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Navigate")
                    .font(AppTypography.ui(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                SidebarNavButton(title: "Dashboard", icon: "rectangle.grid.2x2", section: .dashboard, selection: $selection)
                SidebarNavButton(title: "History", icon: "clock.arrow.circlepath", section: .history, selection: $selection)
                SidebarNavButton(title: "Hotkey", icon: "keyboard", section: .hotkey, selection: $selection)
                SidebarNavButton(title: "Model", icon: "cpu", section: .model, selection: $selection)
                SidebarNavButton(title: "Vocabulary", icon: "text.book.closed", section: .vocabulary, selection: $selection)
                SidebarNavButton(title: "LLM Polish", icon: "wand.and.stars", section: .llmPolish, selection: $selection)
                SidebarNavButton(title: "General", icon: "gearshape", section: .general, selection: $selection)

                Divider()

                Text("Status")
                    .font(AppTypography.ui(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Label("Phase: \(appState.phase.rawValue.capitalized)", systemImage: "waveform")
                    .font(AppTypography.ui(size: 12))
                Label(appState.hasMicPermission ? "Mic Granted" : "Mic Missing", systemImage: "mic")
                    .font(AppTypography.ui(size: 12))
                Label(appState.hasAccessibilityPermission ? "Accessibility Granted" : "Accessibility Missing", systemImage: "accessibility")
                    .font(AppTypography.ui(size: 12))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SidebarNavButton: View {
    let title: String
    let icon: String
    let section: MainWindowSection
    @Binding var selection: MainWindowSection

    var body: some View {
        Button {
            selection = section
        } label: {
            HStack {
                Label(title, systemImage: icon)
                    .font(AppTypography.ui(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selection == section ? AppTheme.cardBackground : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
    }
}
