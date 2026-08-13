import AppKit
import Carbon

protocol HotkeyServiceProtocol: AnyObject {
    var onHotkeyDown: (() -> Void)? { get set }
    var onHotkeyUp: (() -> Void)? { get set }
    var onEditModeHotkeyDown: (() -> Void)? { get set }
    var onEditModeHotkeyUp: (() -> Void)? { get set }
    var onComputerUseHotkeyDown: (() -> Void)? { get set }
    var onComputerUseHotkeyUp: (() -> Void)? { get set }
    var onCancel: (() -> Bool)? { get set }
    var onPasteLastTranscript: (() -> Void)? { get set }
    var onVoiceActivationToggle: (() -> Void)? { get set }
    func startMonitoring(assignments: HotkeySlotAssignments, installCancellationMonitors: Bool)
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
        case computerUse = 3
        case pasteLastTranscript = 4
        case voiceActivationToggle = 5
    }

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onEditModeHotkeyDown: (() -> Void)?
    var onEditModeHotkeyUp: (() -> Void)?
    var onComputerUseHotkeyDown: (() -> Void)?
    var onComputerUseHotkeyUp: (() -> Void)?
    var onCancel: (() -> Bool)?
    var onPasteLastTranscript: (() -> Void)?
    var onVoiceActivationToggle: (() -> Void)?

    private var globeGlobalMonitor: Any?
    private var globeLocalMonitor: Any?
    private var cancellationGlobalMonitor: Any?
    private var cancellationLocalMonitor: Any?
    private var carbonHotKeyRefs: [Slot: EventHotKeyRef] = [:]
    private var carbonEventHandlerRef: EventHandlerRef?
    private var heldSlots: Set<Slot> = []
    private var globeSlot: Slot?

    /// Assignments arrive pairwise-distinct by construction
    /// (`HotkeySlotAssignments` owns the collision policy), so registration is
    /// unconditional.
    func startMonitoring(assignments: HotkeySlotAssignments, installCancellationMonitors: Bool) {
        stopMonitoring()

        register(assignments.dictation, for: .dictation)
        register(assignments.pasteLastTranscript, for: .pasteLastTranscript)
        if let editMode = assignments.editMode {
            register(editMode, for: .editMode)
        }
        if let computerUse = assignments.computerUse {
            register(computerUse, for: .computerUse)
        }
        if let voiceActivationToggle = assignments.voiceActivationToggle {
            register(voiceActivationToggle, for: .voiceActivationToggle)
        }
        // Escape must work while a Computer Use hotkey exists or Voice
        // Activation is on (a listening turn has no hotkey to release).
        if assignments.computerUse != nil || installCancellationMonitors {
            installCancellationMonitorsIfNeeded()
        }
    }

    func stopMonitoring() {
        if let globeGlobalMonitor {
            NSEvent.removeMonitor(globeGlobalMonitor)
            self.globeGlobalMonitor = nil
        }
        if let globeLocalMonitor {
            NSEvent.removeMonitor(globeLocalMonitor)
            self.globeLocalMonitor = nil
        }
        if let cancellationGlobalMonitor {
            NSEvent.removeMonitor(cancellationGlobalMonitor)
            self.cancellationGlobalMonitor = nil
        }
        if let cancellationLocalMonitor {
            NSEvent.removeMonitor(cancellationLocalMonitor)
            self.cancellationLocalMonitor = nil
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
        guard globeGlobalMonitor == nil && globeLocalMonitor == nil else {
            return
        }

        globeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleGlobeEvent(event)
        }

        globeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleGlobeEvent(event)
            return event
        }
    }

    private func installCancellationMonitorsIfNeeded() {
        guard cancellationGlobalMonitor == nil && cancellationLocalMonitor == nil else {
            return
        }

        cancellationGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleCancellationEvent(event)
        }

        cancellationLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleCancellationEvent(event) == true ? nil : event
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

    private func handleGlobeEvent(_ event: NSEvent) {
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

    private func handleCancellationEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_Escape) else {
            return false
        }
        return onCancel?() ?? false
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

    func downCallback(for slot: Slot) -> (() -> Void)? {
        switch slot {
        case .dictation:
            return onHotkeyDown
        case .editMode:
            return onEditModeHotkeyDown
        case .computerUse:
            return onComputerUseHotkeyDown
        case .pasteLastTranscript:
            // The recovery path may synthesize Command+V. Wait until the
            // physical shortcut key is released so the paste is not swallowed.
            return nil
        case .voiceActivationToggle:
            // A toggle acts on release, not press.
            return nil
        }
    }

    func upCallback(for slot: Slot) -> (() -> Void)? {
        switch slot {
        case .dictation:
            return onHotkeyUp
        case .editMode:
            return onEditModeHotkeyUp
        case .computerUse:
            return onComputerUseHotkeyUp
        case .pasteLastTranscript:
            return onPasteLastTranscript
        case .voiceActivationToggle:
            return onVoiceActivationToggle
        }
    }
}
