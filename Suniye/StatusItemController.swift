import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let appState: AppState
    private let appIdentity = AppIdentity.current
    private let statusItem: NSStatusItem

    private let recordMeetingItem = NSMenuItem(title: "Record Meeting", action: #selector(recordMeeting), keyEquivalent: "")
    private let meetingStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseMeetingItem = NSMenuItem(title: "Pause Recording", action: #selector(pauseOrResumeMeeting), keyEquivalent: "")
    private let stopMeetingItem = NSMenuItem(title: "Stop Recording", action: #selector(stopMeeting), keyEquivalent: "")
    private let openMeetingItem = NSMenuItem(title: "Open Meeting", action: #selector(openMeeting), keyEquivalent: "")
    private let finishSetupItem = NSMenuItem(title: "", action: #selector(openMainWindow), keyEquivalent: "")
    private let openSettingsItem = NSMenuItem(title: "Open Settings", action: #selector(openMainWindow), keyEquivalent: "o")
    private let copyLastTranscriptItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "")
    private let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
    private let downloadItem = NSMenuItem(title: "Download Model", action: #selector(downloadModel), keyEquivalent: "d")
    private let reportIssueItem = NSMenuItem(title: "Report a Problem...", action: #selector(reportIssue), keyEquivalent: "")
    private lazy var quitItem = NSMenuItem(title: "Quit \(appIdentity.displayName)", action: #selector(quitApp), keyEquivalent: "q")
    private var onboardingFinishObserver: NSObjectProtocol?
    private var homeHint: NSPopover?

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureMenu()
        refreshWhileObserved()
        onboardingFinishObserver = NotificationCenter.default.addObserver(
            forName: .suniyeOnboardingDidFinish,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showHomeHint()
            }
        }
    }

    /// The window closes when onboarding ends, so point once at where the app
    /// now lives. It leaves on its own; clicking anywhere also dismisses it.
    private func showHomeHint() {
        guard let button = statusItem.button, homeHint == nil else {
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let content = NSHostingController(
            rootView: Text("\(appIdentity.displayName) lives here.")
                .font(.callout.weight(.medium))
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        )
        popover.contentViewController = content
        popover.contentSize = content.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        homeHint = popover
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.homeHint?.performClose(nil)
            self?.homeHint = nil
        }
    }

    private func configureMenu() {
        let menu = NSMenu()

        for item in [recordMeetingItem, pauseMeetingItem, stopMeetingItem, openMeetingItem] {
            item.target = self
        }
        finishSetupItem.target = self
        openSettingsItem.target = self
        copyLastTranscriptItem.target = self
        checkUpdatesItem.target = self
        downloadItem.target = self
        reportIssueItem.target = self
        quitItem.target = self

        // The abandonment-recovery affordance: a user who closes the window
        // mid-setup must see a labeled way back (with live download progress),
        // not a normal-looking menu that silently does nothing.
        menu.addItem(recordMeetingItem)
        menu.addItem(meetingStatusItem)
        menu.addItem(pauseMeetingItem)
        menu.addItem(stopMeetingItem)
        menu.addItem(openMeetingItem)
        menu.addItem(.separator())
        menu.addItem(finishSetupItem)
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

    private func refreshWhileObserved() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshWhileObserved()
            }
        }
    }

    private func refresh() {
        let phase = appState.phase

        let live = appState.meetings.live
        recordMeetingItem.isHidden = live != nil
        for item in [meetingStatusItem, pauseMeetingItem, stopMeetingItem, openMeetingItem] {
            item.isHidden = live == nil
        }
        if let live {
            meetingStatusItem.title = "\(live.isPaused ? "Paused" : "Recording") · \(MeetingTranscript.clock(live.elapsed(at: Date())))"
            pauseMeetingItem.title = live.isPaused ? "Resume Recording" : "Pause Recording"
        }

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

        copyLastTranscriptItem.isEnabled = appState.library.lastTranscriptText != nil

        if appState.isUpdateReadyToInstall {
            checkUpdatesItem.title = "Restart to Update"
            checkUpdatesItem.action = #selector(restartToUpdate)
        } else {
            checkUpdatesItem.title = "Check for Updates..."
            checkUpdatesItem.action = #selector(checkForUpdates)
        }

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
    private func recordMeeting() {
        AppLogger.shared.log(.info, "menu action: record meeting")
        appState.startMeetingFromMenu()
    }

    @objc
    private func pauseOrResumeMeeting() {
        AppLogger.shared.log(.info, "menu action: pause or resume meeting")
        appState.handleMeetingPillAction(appState.meetings.live?.isPaused == true ? .resume : .pause)
    }

    @objc
    private func stopMeeting() {
        AppLogger.shared.log(.info, "menu action: stop meeting")
        appState.handleMeetingPillAction(.stop)
    }

    @objc
    private func openMeeting() {
        AppLogger.shared.log(.info, "menu action: open meeting")
        appState.handleMeetingPillAction(.open)
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
    private func restartToUpdate() {
        AppLogger.shared.log(.info, "menu action: restart to update")
        appState.restartToUpdate()
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

extension StatusItemController: NSMenuItemValidation {
    /// The menu auto-enables its items and ignores `isEnabled`, so the restart
    /// item is greyed here while a dictation runs.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(restartToUpdate) || appState.canRestartToUpdate
    }
}

private extension NSFont {
    func withBoldTrait() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
