import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let appIdentity = AppIdentity.current
    private let statusItem: NSStatusItem

    private let openSettingsItem = NSMenuItem(title: "Open Settings", action: #selector(openMainWindow), keyEquivalent: "o")
    private let copyLastTranscriptItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "")
    private let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
    private let downloadItem = NSMenuItem(title: "Download Model", action: #selector(downloadModel), keyEquivalent: "d")
    private let reportIssueItem = NSMenuItem(title: "Report a Problem...", action: #selector(reportIssue), keyEquivalent: "")
    private lazy var quitItem = NSMenuItem(title: "Quit \(appIdentity.displayName)", action: #selector(quitApp), keyEquivalent: "q")

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureMenu()
        refresh()
        appState.onStateChange = { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self

        openSettingsItem.target = self
        copyLastTranscriptItem.target = self
        checkUpdatesItem.target = self
        downloadItem.target = self
        reportIssueItem.target = self
        quitItem.target = self

        menu.addItem(openSettingsItem)
        menu.addItem(copyLastTranscriptItem)
        menu.addItem(.separator())
        menu.addItem(checkUpdatesItem)
        menu.addItem(downloadItem)
        menu.addItem(.separator())
        menu.addItem(reportIssueItem)
        menu.addItem(quitItem)

        if let button = statusItem.button {
            button.image = statusItemImage(for: appState.phase)
            button.toolTip = appIdentity.displayName
        }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        let phase = appState.phase

        checkUpdatesItem.target = self

        copyLastTranscriptItem.isEnabled = appState.lastTranscriptText != nil

        checkUpdatesItem.title = "Check for Updates..."
        checkUpdatesItem.action = #selector(checkForUpdates)
        checkUpdatesItem.isEnabled = appState.canCheckForUpdates

        downloadItem.isEnabled = phase == .needsModel || phase == .downloadingModel || phase == .error
        downloadItem.isHidden = !(phase == .needsModel || phase == .downloadingModel || phase == .error)

        if let button = statusItem.button {
            button.image = statusItemImage(for: phase)
        }
    }

    private func statusItemImage(for phase: AppState.Phase) -> NSImage? {
        let image: NSImage?
        if let assetImage = NSImage(named: "StatusBarIcon") {
            image = assetImage
        } else {
            let symbolName = phase == .recording ? "mic.fill" : "mic"
            image = NSImage(systemSymbolName: symbolName, accessibilityDescription: appIdentity.displayName)
        }

        guard let image else {
            return nil
        }

        if appIdentity.isPreview {
            return previewBadgedStatusItemImage(from: image)
        }

        let stableImage = image.copy() as? NSImage ?? image
        stableImage.isTemplate = true
        return stableImage
    }

    private func previewBadgedStatusItemImage(from source: NSImage) -> NSImage {
        let size = source.size.width > 0 && source.size.height > 0
            ? source.size
            : NSSize(width: 18, height: 18)

        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size))

        let badgeSize = max(5, min(size.width, size.height) * 0.38)
        let badgeRect = NSRect(
            x: size.width - badgeSize,
            y: size.height - badgeSize,
            width: badgeSize,
            height: badgeSize
        )
        NSColor.black.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        image.unlockFocus()

        image.isTemplate = true
        return image
    }

    @objc
    private func openMainWindow() {
        AppLogger.shared.log(.info, "menu action: open main window")
        appState.openMainWindow()
    }

    @objc
    private func copyLastTranscript() {
        let didCopy = appState.copyLastTranscript()
        AppLogger.shared.log(.info, "menu action: copy last transcript result=\(didCopy ? "copied" : "unavailable")")
    }

    @objc
    private func checkForUpdates() {
        AppLogger.shared.log(.info, "menu action: check updates")
        appState.checkForUpdates()
    }

    @objc
    private func downloadModel() {
        AppLogger.shared.log(.info, "menu action: download model")
        appState.startModelDownload()
    }

    @objc
    private func reportIssue() {
        AppLogger.shared.log(.info, "menu action: report issue")
        appState.openIssueReportWindow()
    }

    @objc
    private func quitApp() {
        AppLogger.shared.log(.info, "menu action: quit app")
        NSApplication.shared.terminate(nil)
    }
}
