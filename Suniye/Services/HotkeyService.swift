import AppKit
import Carbon

protocol HotkeyServiceProtocol: AnyObject {
    var onHotkeyDown: (() -> Void)? { get set }
    var onHotkeyUp: (() -> Void)? { get set }
    var onEditModeHotkeyDown: (() -> Void)? { get set }
    var onEditModeHotkeyUp: (() -> Void)? { get set }
    var onPasteLastTranscript: (() -> Void)? { get set }
    func startMonitoring(
        configuration: HotkeyConfiguration,
        editModeConfiguration: HotkeyConfiguration?,
        pasteLastTranscriptConfiguration: HotkeyConfiguration
    )
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
    enum Slot: UInt32 {
        case dictation = 1
        case editMode = 2
        case pasteLastTranscript = 3
    }

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onEditModeHotkeyDown: (() -> Void)?
    var onEditModeHotkeyUp: (() -> Void)?
    var onPasteLastTranscript: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var carbonHotKeyRefs: [Slot: EventHotKeyRef] = [:]
    private var carbonEventHandlerRef: EventHandlerRef?
    private var heldSlots: Set<Slot> = []
    private var globeSlot: Slot?

    func startMonitoring(
        configuration: HotkeyConfiguration,
        editModeConfiguration: HotkeyConfiguration?,
        pasteLastTranscriptConfiguration: HotkeyConfiguration
    ) {
        stopMonitoring()

        register(configuration, for: .dictation)
        if pasteLastTranscriptConfiguration == configuration {
            AppLogger.shared.log(.warning, "paste last transcript hotkey ignored: matches dictation hotkey")
        } else {
            register(pasteLastTranscriptConfiguration, for: .pasteLastTranscript)
        }
        if let editModeConfiguration {
            if editModeConfiguration == configuration || editModeConfiguration == pasteLastTranscriptConfiguration {
                AppLogger.shared.log(.warning, "edit mode hotkey ignored: matches another hotkey")
            } else {
                register(editModeConfiguration, for: .editMode)
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
        for hotKeyRef in carbonHotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        carbonHotKeyRefs.removeAll()
        if let carbonEventHandlerRef {
            RemoveEventHandler(carbonEventHandlerRef)
            self.carbonEventHandlerRef = nil
        }
        globeSlot = nil
        heldSlots.removeAll()
    }

    private func register(_ configuration: HotkeyConfiguration, for slot: Slot) {
        switch configuration.kind {
        case .globe:
            guard globeSlot == nil else {
                AppLogger.shared.log(.warning, "globe hotkey already registered; skipping slot=\(slot.rawValue)")
                return
            }
            globeSlot = slot
            installGlobeMonitorsIfNeeded()
        case .keyCombo:
            guard installCarbonEventHandlerIfNeeded() else {
                return
            }

            let hotKeyID = EventHotKeyID(signature: OSType(0x53554E49), id: slot.rawValue)
            var hotKeyRef: EventHotKeyRef?
            let registerStatus = RegisterEventHotKey(
                UInt32(configuration.keyCode),
                UInt32(configuration.carbonModifiers),
                hotKeyID,
                GetEventDispatcherTarget(),
                OptionBits(kEventHotKeyExclusive),
                &hotKeyRef
            )

            if registerStatus == noErr, let hotKeyRef {
                carbonHotKeyRefs[slot] = hotKeyRef
            } else {
                // Intentionally leave the other slot alive: one slot failing to
                // register (e.g. combo taken by another app) must not tear down
                // monitoring for the other.
                AppLogger.shared.log(.error, "hotkey registration failed slot=\(slot.rawValue) status=\(registerStatus)")
            }
        }
    }

    private func installGlobeMonitorsIfNeeded() {
        guard globalMonitor == nil && localMonitor == nil else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    private func installCarbonEventHandlerIfNeeded() -> Bool {
        guard carbonEventHandlerRef == nil else {
            return true
        }

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
            return false
        }

        return true
    }

    private func handle(event: NSEvent) {
        guard event.type == .flagsChanged, let globeSlot else {
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let fnDown = flags.contains(.function)

        if fnDown && !heldSlots.contains(globeSlot) {
            heldSlots.insert(globeSlot)
            AppLogger.shared.log(.debug, "hotkey fn down keyCode=\(event.keyCode) slot=\(globeSlot.rawValue)")
            downCallback(for: globeSlot)?()
        } else if !fnDown && heldSlots.contains(globeSlot) {
            heldSlots.remove(globeSlot)
            AppLogger.shared.log(.debug, "hotkey fn up keyCode=\(event.keyCode) slot=\(globeSlot.rawValue)")
            upCallback(for: globeSlot)?()
        }
    }

    fileprivate func handleCarbonEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else {
            return noErr
        }

        var hotKeyID = EventHotKeyID()
        let paramStatus = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard paramStatus == noErr, let slot = Slot(rawValue: hotKeyID.id) else {
            return noErr
        }

        switch GetEventKind(eventRef) {
        case UInt32(kEventHotKeyPressed):
            guard !heldSlots.contains(slot) else { return noErr }
            heldSlots.insert(slot)
            AppLogger.shared.log(.debug, "hotkey combo down slot=\(slot.rawValue)")
            downCallback(for: slot)?()
        case UInt32(kEventHotKeyReleased):
            guard heldSlots.contains(slot) else { return noErr }
            heldSlots.remove(slot)
            AppLogger.shared.log(.debug, "hotkey combo up slot=\(slot.rawValue)")
            upCallback(for: slot)?()
        default:
            break
        }

        return noErr
    }

    private func downCallback(for slot: Slot) -> (() -> Void)? {
        switch slot {
        case .dictation:
            return onHotkeyDown
        case .editMode:
            return onEditModeHotkeyDown
        case .pasteLastTranscript:
            return onPasteLastTranscript
        }
    }

    private func upCallback(for slot: Slot) -> (() -> Void)? {
        switch slot {
        case .dictation:
            return onHotkeyUp
        case .editMode:
            return onEditModeHotkeyUp
        case .pasteLastTranscript:
            return nil
        }
    }
}
