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

struct SidebarView: View {
    @Bindable var appState: AppState
    @Binding var selection: MainWindowSection

    var body: some View {
        List(selection: $selection) {
            Section("Navigate") {
                ForEach(MainWindowSection.allCases, id: \.self) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }

            Section("Status") {
                Label("Phase: \(appState.phase.rawValue.capitalized)", systemImage: "waveform")
                Label(appState.hasMicPermission ? "Microphone: Granted" : "Microphone: Missing", systemImage: "mic")
                Label(appState.hasAccessibilityPermission ? "Accessibility: Granted" : "Accessibility: Missing", systemImage: "accessibility")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("VibeStoke")
    }
}
