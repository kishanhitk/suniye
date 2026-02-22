import AppKit
import OSLog
import SwiftUI

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private let logger = Logger(subsystem: "dev.vibestroke.app", category: "window")

    private var window: NSWindow?

    private init() {}

    func show(appState: AppState) {
        NSApp.setActivationPolicy(.regular)

        if let window {
            logger.notice("show existing main window")
            AppLogger.shared.log(.info, "show existing main window")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        logger.notice("create main window")
        AppLogger.shared.log(.info, "create main window")

        let content = MainWindowView(appState: appState)
            .frame(minWidth: 780, minHeight: 520)

        let host = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VibeStoke"
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.contentView = host

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

@MainActor
final class AppLaunchDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger(subsystem: "dev.vibestroke.app", category: "window").notice("applicationDidFinishLaunching")
        AppLogger.shared.log(.info, "applicationDidFinishLaunching")
        statusItemController = StatusItemController(appState: sharedAppState)
        MainWindowController.shared.show(appState: sharedAppState)
        if CommandLine.arguments.contains("--e2e-indicator-smoke") {
            sharedAppState.runIndicatorE2ESmoke()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Logger(subsystem: "dev.vibestroke.app", category: "window").notice("applicationShouldHandleReopen")
        AppLogger.shared.log(.info, "applicationShouldHandleReopen")
        MainWindowController.shared.show(appState: sharedAppState)
        return true
    }
}
