import SwiftUI

struct SidebarView: View {
    @Binding var selection: MainWindowSection

    var body: some View {
        List(selection: $selection) {
            ForEach(MainWindowSection.allCases, id: \.self) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("VibeStoke")
    }
}
