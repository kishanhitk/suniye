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

        let content = MainWindowRootView(appState: appState)
            .frame(minWidth: 780, minHeight: 620)

        let host = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppIdentity.current.displayName
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

    func windowWillClose(_ notification: Notification) {
        // Revert to a pure menu-bar app when the window closes — but keep the
        // Dock icon (a second resume affordance) while onboarding is unfinished.
        guard appState?.onboardingProgress.isFinished ?? true else {
            return
        }
        AppLogger.shared.log(.info, "main window closing; reverting activation policy")
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MainWindowRootView: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            if appState.activeOnboardingStep != nil {
                OnboardingView(appState: appState)
            } else {
                MainWindowView(appState: appState)
            }
        }
        .background(MainWindowPalette.windowBackground)
    }
}

@MainActor
final class AppLaunchDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var workspaceObservers: [NSObjectProtocol] = []

    deinit {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger(subsystem: "dev.suniye.app", category: "window").notice("applicationDidFinishLaunching")
        AppLogger.shared.log(.info, "applicationDidFinishLaunching")
        statusItemController = StatusItemController(appState: sharedAppState)
        observeWorkspaceLifecycle()
        MainWindowController.shared.show(appState: sharedAppState)
        if ProcessInfo.processInfo.shouldStartUpdateController {
            sharedAppState.startUpdateController()
        }
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
        sharedAppState.refreshInputDevices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Durably enqueue session_end. We do NOT await a flush here — the process
        // may exit first; the atomic on-disk queue means the event (and any
        // unsent events) ship on the next launch.
        sharedAppState.recordAnalyticsSessionEnd()
    }

    private func observeWorkspaceLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    AppLogger.shared.log(.info, "system will sleep")
                    await sharedAppState.handleSystemWillSleep()
                    await sharedAppState.flushAnalytics()
                }
            },
            center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    AppLogger.shared.log(.info, "system will power off")
                    sharedAppState.recordAnalyticsSessionEnd()
                    await sharedAppState.flushAnalytics()
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    AppLogger.shared.log(.info, "system did wake")
                    sharedAppState.handleSystemDidWake()
                }
            },
        ]
    }
}
