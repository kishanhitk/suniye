import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem

    private let statusTitleItem = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
    private let startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "r")
    private let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "s")
    private let openWindowItem = NSMenuItem(title: "Open VibeStoke", action: #selector(openMainWindow), keyEquivalent: "o")
    private let downloadItem = NSMenuItem(title: "Download Model", action: #selector(downloadModel), keyEquivalent: "d")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility Permission", action: #selector(requestAccessibility), keyEquivalent: "a")
    private let openLogsItem = NSMenuItem(title: "Open Logs Folder", action: #selector(openLogs), keyEquivalent: "l")
    private let quitItem = NSMenuItem(title: "Quit VibeStoke", action: #selector(quitApp), keyEquivalent: "q")

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

        startItem.target = self
        stopItem.target = self
        openWindowItem.target = self
        downloadItem.target = self
        accessibilityItem.target = self
        openLogsItem.target = self
        quitItem.target = self

        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(openWindowItem)
        menu.addItem(downloadItem)
        menu.addItem(accessibilityItem)
        menu.addItem(openLogsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VibeStoke")
            button.image?.isTemplate = true
            button.toolTip = "VibeStoke"
        }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        let phase = appState.phase
        statusTitleItem.title = "Status: \(phase.rawValue.capitalized)"
        startItem.isEnabled = phase == .ready
        stopItem.isEnabled = phase == .recording
        downloadItem.isEnabled = phase == .needsModel || phase == .downloadingModel || phase == .error

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: phase == .recording ? "mic.fill" : "mic", accessibilityDescription: "VibeStoke")
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
