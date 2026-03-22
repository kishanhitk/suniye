import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem

    private let statusTitleItem = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
    private let openSettingsItem = NSMenuItem(title: "Open Settings", action: #selector(openMainWindow), keyEquivalent: "o")
    private let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
    private let downloadUpdateItem = NSMenuItem(title: "Download Update", action: #selector(downloadUpdate), keyEquivalent: "")
    private let downloadItem = NSMenuItem(title: "Download Model", action: #selector(downloadModel), keyEquivalent: "d")
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

        statusTitleItem.isEnabled = false
        menu.addItem(statusTitleItem)
        menu.addItem(.separator())

        openSettingsItem.target = self
        checkUpdatesItem.target = self
        downloadUpdateItem.target = self
        downloadItem.target = self
        quitItem.target = self

        menu.addItem(openSettingsItem)
        menu.addItem(checkUpdatesItem)
        menu.addItem(downloadUpdateItem)
        menu.addItem(downloadItem)
        menu.addItem(.separator())
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
        statusTitleItem.title = "Status: \(phase.rawValue.capitalized)"

        let updateStatus = appState.updateStatus
        checkUpdatesItem.isEnabled = updateStatus != .checking && updateStatus != .downloading

        switch updateStatus {
        case .checking:
            checkUpdatesItem.title = "Checking for Updates..."
        case .available:
            if let version = appState.availableUpdateVersion {
                checkUpdatesItem.title = "Update Available: \(version)"
            } else {
                checkUpdatesItem.title = "Update Available"
            }
        case .upToDate:
            checkUpdatesItem.title = "Up to Date"
        case .downloading:
            checkUpdatesItem.title = "Downloading Update..."
        case .error:
            checkUpdatesItem.title = "Check for Updates..."
        case .idle:
            checkUpdatesItem.title = "Check for Updates..."
        }

        downloadUpdateItem.target = self
        downloadUpdateItem.isHidden = updateStatus != .available
        downloadUpdateItem.isEnabled = updateStatus == .available

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
    private func checkForUpdates() {
        AppLogger.shared.log(.info, "menu action: check updates")
        Task {
            await appState.checkForUpdates(background: false)
        }
    }

    @objc
    private func downloadUpdate() {
        AppLogger.shared.log(.info, "menu action: download update")
        Task {
            await appState.downloadAndOpenUpdate()
        }
    }

    @objc
    private func downloadModel() {
        AppLogger.shared.log(.info, "menu action: download model")
        appState.startModelDownload()
    }

    @objc
    private func quitApp() {
        AppLogger.shared.log(.info, "menu action: quit app")
        NSApplication.shared.terminate(nil)
    }
}
