import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let appIdentity = AppIdentity.current
    private let statusItem: NSStatusItem

    private let finishSetupItem = NSMenuItem(title: "", action: #selector(openMainWindow), keyEquivalent: "")
    private let openSettingsItem = NSMenuItem(title: "Open Settings", action: #selector(openMainWindow), keyEquivalent: "o")
    private let copyLastTranscriptItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "")
    private let newComputerUseConversationItem = NSMenuItem(
        title: "New Computer Use Conversation",
        action: #selector(startNewComputerUseConversation),
        keyEquivalent: ""
    )
    private let voiceActivationToggleItem = NSMenuItem(
        title: "Turn Voice Activation On",
        action: #selector(toggleVoiceActivation),
        keyEquivalent: ""
    )
    private let stopComputerUseTaskItem = NSMenuItem(
        title: "Stop Current Task",
        action: #selector(stopComputerUseTask),
        keyEquivalent: ""
    )
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

        finishSetupItem.target = self
        openSettingsItem.target = self
        copyLastTranscriptItem.target = self
        newComputerUseConversationItem.target = self
        voiceActivationToggleItem.target = self
        stopComputerUseTaskItem.target = self
        checkUpdatesItem.target = self
        downloadItem.target = self
        reportIssueItem.target = self
        quitItem.target = self

        // The abandonment-recovery affordance: a user who closes the window
        // mid-setup must see a labeled way back (with live download progress),
        // not a normal-looking menu that silently does nothing.
        menu.addItem(finishSetupItem)
        menu.addItem(openSettingsItem)
        menu.addItem(copyLastTranscriptItem)
        menu.addItem(newComputerUseConversationItem)
        menu.addItem(voiceActivationToggleItem)
        menu.addItem(stopComputerUseTaskItem)
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

        if let setupTitle = appState.setupMenuItemTitle {
            finishSetupItem.isHidden = false
            finishSetupItem.title = setupTitle
            finishSetupItem.attributedTitle = NSAttributedString(
                string: setupTitle,
                attributes: [.font: NSFont.menuFont(ofSize: 0).withBoldTrait()]
            )
        } else {
            finishSetupItem.isHidden = true
        }

        checkUpdatesItem.target = self

        copyLastTranscriptItem.isEnabled = appState.lastTranscriptText != nil
        newComputerUseConversationItem.isEnabled = !appState.computerUseCoordinator.isRunning
            && !appState.computerUseCoordinator.conversation.isEmpty

        // UX plan: the menu bar always tells the user whether Suniye is
        // waiting for the wake phrase.
        voiceActivationToggleItem.title = appState.voiceActivationEnabled
            ? "Turn Voice Activation Off"
            : "Turn Voice Activation On"
        stopComputerUseTaskItem.isEnabled = appState.computerUseCoordinator.isRunning
        stopComputerUseTaskItem.isHidden = !appState.computerUseCoordinator.isRunning

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
    private func startNewComputerUseConversation() {
        AppLogger.shared.log(.info, "menu action: new computer use conversation")
        appState.startNewComputerUseConversation()
    }

    @objc
    private func toggleVoiceActivation() {
        AppLogger.shared.log(.info, "menu action: toggle voice activation")
        appState.toggleVoiceActivation()
    }

    @objc
    private func stopComputerUseTask() {
        AppLogger.shared.log(.info, "menu action: stop computer use task")
        appState.computerUseCoordinator.stop()
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

private extension NSFont {
    func withBoldTrait() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
