import SwiftUI

@MainActor
let sharedAppState = AppState(startServices: ProcessInfo.processInfo.shouldStartRuntimeServices)

@main
struct SuniyeApp: App {
    @NSApplicationDelegateAdaptor(AppLaunchDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(after: .help) {
                Button("Report a Problem...") {
                    sharedAppState.openIssueReportWindow()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
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
