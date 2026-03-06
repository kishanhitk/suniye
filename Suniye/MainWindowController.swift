import AppKit
import OSLog
import SwiftUI

extension Notification.Name {
    static let suniyeToggleSidebar = Notification.Name("dev.suniye.window.toggleSidebar")
}

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private let logger = Logger(subsystem: "dev.suniye.app", category: "window")

    private var window: NSWindow?
    private let toolbarDelegate = MainWindowToolbarDelegate()

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
            .frame(minWidth: 1024, minHeight: 700)

        let host = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Suniye"
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        if #available(macOS 12, *) { window.titlebarSeparatorStyle = .none }
        window.toolbar = toolbarDelegate.makeToolbar()
        window.contentView = host

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

@MainActor
private final class MainWindowToolbarDelegate: NSObject, NSToolbarDelegate {
    private let sidebarItemIdentifier = NSToolbarItem.Identifier("dev.suniye.toolbar.sidebar")

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "dev.suniye.window.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .default
        toolbar.showsBaselineSeparator = false
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [sidebarItemIdentifier, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [sidebarItemIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == sidebarItemIdentifier else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Toggle Sidebar"
        item.paletteLabel = "Toggle Sidebar"
        item.toolTip = "Toggle Sidebar"
        item.isBordered = true
        item.target = self
        item.action = #selector(toggleSidebar)
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
        return item
    }

    @objc private func toggleSidebar() {
        NotificationCenter.default.post(name: .suniyeToggleSidebar, object: nil)
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
}
