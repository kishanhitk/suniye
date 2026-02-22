import AppKit

final class HotkeyService {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isHeld = false

    private let fnKeyCode: UInt16 = 179

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
        guard !event.isARepeat else {
            return
        }

        let isFnEvent = event.keyCode == fnKeyCode
        guard isFnEvent else {
            return
        }

        let fnDown = event.modifierFlags.contains(.function)

        if fnDown && !isHeld {
            isHeld = true
            onHotkeyDown?()
        } else if !fnDown && isHeld {
            isHeld = false
            onHotkeyUp?()
        }
    }
}
