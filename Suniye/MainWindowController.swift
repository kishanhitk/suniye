import AppKit
import OSLog
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()
    private let logger = Logger(subsystem: "dev.suniye.app", category: "window")

    private var window: NSWindow?
    private weak var appState: AppState?

    private override init() {}

    func show(appState: AppState) {
        self.appState = appState
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
            .frame(minWidth: 680, minHeight: 560)

        let host = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Suniye"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = MainWindowPalette.windowBackgroundNSColor
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.delegate = self
        window.contentView = host

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        AppLogger.shared.log(.info, "main window became key; refreshing permission status")
        appState?.refreshPermissionStatus()
    }
}

@MainActor
final class AppLaunchDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger(subsystem: "dev.suniye.app", category: "window").notice("applicationDidFinishLaunching")
        AppLogger.shared.log(.info, "applicationDidFinishLaunching")
        statusItemController = StatusItemController(appState: sharedAppState)
        MainWindowController.shared.show(appState: sharedAppState)
        sharedAppState.startAutomaticUpdateChecks()
        if CommandLine.arguments.contains("--e2e-indicator-smoke") {
            sharedAppState.runIndicatorE2ESmoke()
        }
        if CommandLine.arguments.contains("--e2e-llm-success") || CommandLine.arguments.contains("--e2e-llm-fallback") {
            sharedAppState.runLLME2ESmoke()
        }
        if CommandLine.arguments.contains("--e2e-submit-command") {
            sharedAppState.runSubmitCommandE2ESmoke()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Logger(subsystem: "dev.suniye.app", category: "window").notice("applicationShouldHandleReopen")
        AppLogger.shared.log(.info, "applicationShouldHandleReopen")
        MainWindowController.shared.show(appState: sharedAppState)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppLogger.shared.log(.info, "applicationDidBecomeActive; refreshing permission status")
        sharedAppState.refreshPermissionStatus()
        Task {
            await sharedAppState.performAutomaticUpdateCheckIfEligible()
        }
    }
}
