import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem

    private let openSettingsItem = NSMenuItem(title: "Open Settings", action: #selector(openMainWindow), keyEquivalent: "o")
    private let copyLastTranscriptItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "")
    private let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
    private let downloadItem = NSMenuItem(title: "Download Model", action: #selector(downloadModel), keyEquivalent: "d")
    private let reportIssueItem = NSMenuItem(title: "Report a Problem...", action: #selector(reportIssue), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Suniye", action: #selector(quitApp), keyEquivalent: "q")

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
            button.toolTip = "Suniye"
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
        if let image = NSImage(named: "StatusBarIcon") {
            image.isTemplate = true
            return image
        }

        let symbolName = phase == .recording ? "mic.fill" : "mic"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Suniye")
        image?.isTemplate = true
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
