import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem

    private let statusTitleItem = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
    private let llmHintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let updateHintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "r")
    private let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "s")
    private let openWindowItem = NSMenuItem(title: "Open Suniye", action: #selector(openMainWindow), keyEquivalent: "o")
    private let downloadItem = NSMenuItem(title: "Download Model", action: #selector(downloadModel), keyEquivalent: "d")
    private let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
    private let downloadUpdateItem = NSMenuItem(title: "Download Update...", action: #selector(downloadUpdate), keyEquivalent: "")
    private let viewReleaseNotesItem = NSMenuItem(title: "View Release Notes", action: #selector(openReleaseNotes), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility Permission", action: #selector(requestAccessibility), keyEquivalent: "a")
    private let openLogsItem = NSMenuItem(title: "Open Logs Folder", action: #selector(openLogs), keyEquivalent: "l")
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
        llmHintItem.isEnabled = false
        updateHintItem.isEnabled = false
        menu.addItem(statusTitleItem)
        menu.addItem(llmHintItem)
        menu.addItem(updateHintItem)
        llmHintItem.isHidden = true
        updateHintItem.isHidden = true
        menu.addItem(.separator())

        startItem.target = self
        stopItem.target = self
        openWindowItem.target = self
        downloadItem.target = self
        checkUpdatesItem.target = self
        downloadUpdateItem.target = self
        viewReleaseNotesItem.target = self
        accessibilityItem.target = self
        openLogsItem.target = self
        quitItem.target = self

        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(openWindowItem)
        menu.addItem(downloadItem)
        menu.addItem(.separator())
        menu.addItem(checkUpdatesItem)
        menu.addItem(downloadUpdateItem)
        menu.addItem(viewReleaseNotesItem)
        menu.addItem(accessibilityItem)
        menu.addItem(openLogsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Suniye")
            button.image?.isTemplate = true
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
        if let hint = appState.llmStatusHint {
            llmHintItem.title = "LLM: \(hint)"
            llmHintItem.isHidden = false
        } else {
            llmHintItem.isHidden = true
        }

        let updateLabel: String?
        switch appState.updateStatus {
        case .idle:
            updateLabel = nil
        case .available:
            updateLabel = appState.availableUpdateVersion.map { "Update: available (\($0))" } ?? "Update: available"
        case .checking, .downloading, .upToDate, .error:
            updateLabel = "Update: \(appState.updateStatusText)"
        }
        if let updateLabel {
            updateHintItem.title = updateLabel
            updateHintItem.isHidden = false
        } else {
            updateHintItem.isHidden = true
        }

        startItem.isEnabled = phase == .ready
        stopItem.isEnabled = phase == .recording
        downloadItem.isEnabled = phase == .needsModel || phase == .downloadingModel || phase == .error
        checkUpdatesItem.isEnabled = appState.updateStatus != .checking && appState.updateStatus != .downloading
        downloadUpdateItem.isEnabled = appState.updateStatus == .available
        if let version = appState.availableUpdateVersion {
            downloadUpdateItem.title = "Download Update \(version)..."
        } else {
            downloadUpdateItem.title = "Download Update..."
        }
        viewReleaseNotesItem.isEnabled = appState.updateStatus == .available

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: phase == .recording ? "mic.fill" : "mic", accessibilityDescription: "Suniye")
            button.image?.isTemplate = true
        }
    }

    @objc
    private func startRecording() {
        AppLogger.shared.log(.info, "menu action: start recording")
        appState.startRecordingFromUI()
    }

    @objc
    private func stopRecording() {
        AppLogger.shared.log(.info, "menu action: stop recording")
        appState.stopRecordingFromUI()
    }

    @objc
    private func openMainWindow() {
        AppLogger.shared.log(.info, "menu action: open main window")
        appState.openMainWindow()
    }

    @objc
    private func downloadModel() {
        AppLogger.shared.log(.info, "menu action: download model")
        appState.startModelDownload()
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
    private func openReleaseNotes() {
        AppLogger.shared.log(.info, "menu action: open release notes")
        appState.openReleaseNotes()
    }

    @objc
    private func requestAccessibility() {
        AppLogger.shared.log(.info, "menu action: request accessibility permission")
        appState.requestAccessibilityPermission()
    }

    @objc
    private func openLogs() {
        AppLogger.shared.log(.info, "menu action: open logs folder")
        NSWorkspace.shared.open(AppLogger.shared.logFileURL.deletingLastPathComponent())
    }

    @objc
    private func quitApp() {
        AppLogger.shared.log(.info, "menu action: quit app")
        NSApplication.shared.terminate(nil)
    }
}
