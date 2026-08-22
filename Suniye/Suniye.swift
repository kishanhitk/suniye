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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    sharedAppState.checkForUpdates()
                }
                .disabled(!sharedAppState.canCheckForUpdates)
            }

            CommandGroup(after: .help) {
                Button("Report a Problem...") {
                    sharedAppState.openIssueReportWindow()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
    }
}

extension ProcessInfo {
    var isRunningUnderXCTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    var shouldStartUpdateController: Bool {
        if isRunningUnderXCTest {
            return false
        }

        return !CommandLine.arguments.contains { $0.hasPrefix("--e2e-") }
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
