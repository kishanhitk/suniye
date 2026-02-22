import SwiftUI

@main
struct VibeStokeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
                .frame(width: 320)
        } label: {
            Image(systemName: appState.phase == .recording ? "mic.fill" : "mic")
        }
        .menuBarExtraStyle(.window)

        Window("VibeStoke", id: "main-window") {
            MainWindowView(appState: appState)
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 920, height: 620)

        Window("Listening", id: "overlay-window") {
            ListeningOverlay(isVisible: appState.showListeningOverlay)
                .ignoresSafeArea()
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 240, height: 240)
    }
}
