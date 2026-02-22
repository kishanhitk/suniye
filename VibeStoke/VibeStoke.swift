import SwiftUI

@MainActor
let sharedAppState = AppState(startServices: ProcessInfo.processInfo.shouldStartRuntimeServices)

@main
struct VibeStokeApp: App {
    @NSApplicationDelegateAdaptor(AppLaunchDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private extension ProcessInfo {
    var isRunningUnderXCTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    var shouldStartRuntimeServices: Bool {
        if isRunningUnderXCTest {
            return false
        }

        let args = Set(CommandLine.arguments)
        if args.contains("--e2e-llm-success") ||
            args.contains("--e2e-llm-fallback") ||
            args.contains("--e2e-submit-command") {
            return false
        }

        return true
    }
}
