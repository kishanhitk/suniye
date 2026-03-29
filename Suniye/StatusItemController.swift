import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem

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

        let updateStatus = appState.updateStatus
        checkUpdatesItem.target = self

        switch updateStatus {
        case .checking:
            checkUpdatesItem.title = "Checking for Updates..."
            checkUpdatesItem.action = nil
            checkUpdatesItem.isEnabled = false
        case .available:
            if let version = appState.availableUpdateVersion {
                checkUpdatesItem.title = "Download Update: \(version)"
            } else {
                checkUpdatesItem.title = "Download Update"
            }
            checkUpdatesItem.action = #selector(downloadUpdate)
            checkUpdatesItem.isEnabled = true
        case .upToDate:
            checkUpdatesItem.title = "Up to Date"
            checkUpdatesItem.action = #selector(checkForUpdates)
            checkUpdatesItem.isEnabled = true
        case .downloading:
            checkUpdatesItem.title = "Downloading Update..."
            checkUpdatesItem.action = nil
            checkUpdatesItem.isEnabled = false
        case .downloaded:
            if let version = appState.availableUpdateVersion {
                checkUpdatesItem.title = "Install Update: \(version)"
            } else {
                checkUpdatesItem.title = "Install Update"
            }
            checkUpdatesItem.action = #selector(downloadUpdate)
            checkUpdatesItem.isEnabled = true
        case .error:
            checkUpdatesItem.title = "Check for Updates..."
            checkUpdatesItem.action = #selector(checkForUpdates)
            checkUpdatesItem.isEnabled = true
        case .idle:
            checkUpdatesItem.title = "Check for Updates..."
            checkUpdatesItem.action = #selector(checkForUpdates)
            checkUpdatesItem.isEnabled = true
        }

        downloadUpdateItem.target = self
        downloadUpdateItem.action = #selector(downloadUpdate)
        downloadUpdateItem.title = updateStatus == .downloaded ? "Install Update" : "Download Update"
        downloadUpdateItem.isHidden = true
        downloadUpdateItem.isEnabled = false

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
