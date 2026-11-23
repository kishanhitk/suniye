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
            // Replaces the item of the empty Settings scene above: Settings is
            // part of the main window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    sharedAppState.openMainWindow(at: .settings())
                }
                .keyboardShortcut(",", modifiers: .command)

                Button("Search Settings") {
                    sharedAppState.openMainWindow(at: .settingsSearch)
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                if sharedAppState.isUpdateReadyToInstall {
                    Button("Restart to Update") {
                        sharedAppState.restartToUpdate()
                    }
                    .disabled(!sharedAppState.canRestartToUpdate)
                } else {
                    Button("Check for Updates…") {
                        sharedAppState.checkForUpdates()
                    }
                    .disabled(!sharedAppState.canCheckForUpdates)
                }
            }

            CommandGroup(after: .help) {
                Button("Report a Problem…") {
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
        if args.contains("--e2e-llm-success") || args.contains("--e2e-llm-fallback") {
            return false
        }

        return true
    }
}
