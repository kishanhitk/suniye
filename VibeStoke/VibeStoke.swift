import SwiftUI

@MainActor
let sharedAppState = AppState()

@main
struct VibeStokeApp: App {
    @NSApplicationDelegateAdaptor(AppLaunchDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
