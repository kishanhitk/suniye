import AppKit
import Carbon

protocol HotkeyServiceProtocol: AnyObject {
    var onHotkeyDown: (() -> Void)? { get set }
    var onHotkeyUp: (() -> Void)? { get set }
    func startMonitoring(configuration: HotkeyConfiguration)
    func stopMonitoring()
}

private let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData else {
        return noErr
    }
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    return service.handleCarbonEvent(eventRef)
}

final class HotkeyService: HotkeyServiceProtocol {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandlerRef: EventHandlerRef?
    private var isHeld = false

    func startMonitoring(configuration: HotkeyConfiguration) {
        stopMonitoring()

        switch configuration.kind {
        case .globe:
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handle(event: event)
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handle(event: event)
                return event
            }
        case .keyCombo:
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]

            let installStatus = InstallEventHandler(
                GetEventDispatcherTarget(),
                hotKeyEventHandler,
                eventTypes.count,
                &eventTypes,
                Unmanaged.passUnretained(self).toOpaque(),
                &carbonEventHandlerRef
            )

            guard installStatus == noErr else {
                AppLogger.shared.log(.error, "hotkey event handler install failed status=\(installStatus)")
                return
            }

            var hotKeyID = EventHotKeyID(signature: OSType(0x53554E49), id: UInt32(1))
            let registerStatus = RegisterEventHotKey(
                UInt32(configuration.keyCode),
                UInt32(configuration.carbonModifiers),
                hotKeyID,
                GetEventDispatcherTarget(),
                OptionBits(kEventHotKeyExclusive),
                &carbonHotKeyRef
            )

            if registerStatus != noErr {
                AppLogger.shared.log(.error, "hotkey registration failed status=\(registerStatus)")
                stopMonitoring()
            }
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
        if let carbonHotKeyRef {
            UnregisterEventHotKey(carbonHotKeyRef)
            self.carbonHotKeyRef = nil
        }
        if let carbonEventHandlerRef {
            RemoveEventHandler(carbonEventHandlerRef)
            self.carbonEventHandlerRef = nil
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

    fileprivate func handleCarbonEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else {
            return noErr
        }

        switch GetEventKind(eventRef) {
        case UInt32(kEventHotKeyPressed):
            guard !isHeld else { return noErr }
            isHeld = true
            AppLogger.shared.log(.debug, "hotkey combo down")
            onHotkeyDown?()
        case UInt32(kEventHotKeyReleased):
            guard isHeld else { return noErr }
            isHeld = false
            AppLogger.shared.log(.debug, "hotkey combo up")
            onHotkeyUp?()
        default:
            break
        }

        return noErr
    }
}
