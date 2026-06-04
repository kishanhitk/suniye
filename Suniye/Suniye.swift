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
            args.contains("--e2e-submit-command") ||
            args.contains("--e2e-audio-aec") {
            return false
        }

        return true
    }
}
