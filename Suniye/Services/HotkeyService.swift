import AppKit

final class HotkeyService {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isHeld = false

    func startMonitoring() {
        stopMonitoring()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isHeld = false
    }

    private func handle(event: NSEvent) {
        guard event.type == .flagsChanged else {
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let fnDown = flags.contains(.function)

        if fnDown && !isHeld {
            isHeld = true
            AppLogger.shared.log(.debug, "hotkey fn down keyCode=\(event.keyCode)")
            onHotkeyDown?()
        } else if !fnDown && isHeld {
            isHeld = false
            AppLogger.shared.log(.debug, "hotkey fn up keyCode=\(event.keyCode)")
            onHotkeyUp?()
        }
    }
}
