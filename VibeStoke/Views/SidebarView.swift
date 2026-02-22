import SwiftUI

enum MainWindowSection: String, CaseIterable, Hashable {
    case stats
    case settings
    case about
}

struct SidebarView: View {
    @Bindable var appState: AppState
    @Binding var selection: MainWindowSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Navigate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                SidebarNavButton(title: "Stats", icon: "chart.bar", section: .stats, selection: $selection)
                SidebarNavButton(title: "Settings", icon: "gearshape", section: .settings, selection: $selection)
                SidebarNavButton(title: "About", icon: "info.circle", section: .about, selection: $selection)

                Divider()

                Text("Status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Label("Phase: \(appState.phase.rawValue.capitalized)", systemImage: "waveform")
                Label(appState.hasMicPermission ? "Mic Granted" : "Mic Missing", systemImage: "mic")
                Label(appState.hasAccessibilityPermission ? "Accessibility Granted" : "Accessibility Missing", systemImage: "accessibility")
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
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selection == section ? Color.gray.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
    }
}
