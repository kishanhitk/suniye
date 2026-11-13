import AppKit
import SwiftUI

@MainActor
final class IssueReportWindowController: NSObject, NSWindowDelegate {
    static let shared = IssueReportWindowController()

    private var window: NSWindow?
    private weak var form: IssueReportForm?

    private override init() {}

    func show(form: IssueReportForm) {
        NSApp.setActivationPolicy(.regular)
        self.form = form

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let content = IssueReportView(form: form) { [weak self] in
            self?.window?.performClose(nil)
        }
            .frame(minWidth: 560, minHeight: 580)
        let host = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Report a Problem"
        window.backgroundColor = MainWindowPalette.windowBackgroundNSColor
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = host

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        form?.windowDidClose()
        form = nil
        window = nil
    }
}
