import AppKit
import Carbon

protocol HotkeyServiceProtocol: AnyObject {
    var onHotkeyDown: (() -> Void)? { get set }
    var onHotkeyUp: (() -> Void)? { get set }
    /// Another key went down while the Globe dictation shortcut is held, as in
    /// fn+Delete. Key events reach Suniye only with Accessibility.
    var onHotkeyChord: (() -> Void)? { get set }
    var onEditModeHotkeyDown: (() -> Void)? { get set }
    var onEditModeHotkeyUp: (() -> Void)? { get set }
    var onPasteLastTranscript: (() -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }
    func startMonitoring(
        configuration: HotkeyConfiguration,
        editModeConfiguration: HotkeyConfiguration?,
        pasteLastTranscriptConfiguration: HotkeyConfiguration
    )
    func stopMonitoring()
    /// While enabled, Esc is taken from other apps and calls `onCancel`. A key
    /// press or a click in another app gives Esc back to the apps until the
    /// next enable, so an Esc meant for a dialog cannot end a dictation.
    func setCancelShortcutEnabled(_ enabled: Bool)
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
        case cancel = 4
    }

    private static let cancelConfiguration = HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_Escape), carbonModifiers: 0)

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onHotkeyChord: (() -> Void)?
    var onEditModeHotkeyDown: (() -> Void)?
    var onEditModeHotkeyUp: (() -> Void)?
    var onPasteLastTranscript: (() -> Void)?
    var onCancel: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var otherInputMonitor: Any?
    private var carbonHotKeyRefs: [Slot: EventHotKeyRef] = [:]
    private var carbonEventHandlerRef: EventHandlerRef?
    private var heldSlots: Set<Slot> = []
    private var globeSlot: Slot?
    private var dictationConfiguration: HotkeyConfiguration?

    func startMonitoring(
        configuration: HotkeyConfiguration,
        editModeConfiguration: HotkeyConfiguration?,
        pasteLastTranscriptConfiguration: HotkeyConfiguration
    ) {
        stopMonitoring()

        dictationConfiguration = configuration
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
        removeOtherInputMonitor()
        for hotKeyRef in carbonHotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        carbonHotKeyRefs.removeAll()
        if let carbonEventHandlerRef {
            RemoveEventHandler(carbonEventHandlerRef)
            self.carbonEventHandlerRef = nil
        }
        globeSlot = nil
        dictationConfiguration = nil
        heldSlots.removeAll()
    }

    func setCancelShortcutEnabled(_ enabled: Bool) {
        releaseCancelShortcut()
        guard enabled else {
            return
        }
        register(Self.cancelConfiguration, for: .cancel)
        // Key events reach a global monitor only with Accessibility; clicks
        // always do.
        otherInputMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            if event.type == .keyDown,
               event.keyCode == UInt16(kVK_Escape) || isDictationShortcutKey(event.keyCode) {
                return
            }
            AppLogger.shared.log(.debug, "cancel shortcut released: input in another app")
            releaseCancelShortcut()
        }
    }

    /// The shortcut's own key is neither a chord nor input in another app. With
    /// Karabiner-Elements running, Globe also sends its own key, code 179.
    private func isDictationShortcutKey(_ keyCode: UInt16) -> Bool {
        guard let dictationConfiguration else {
            return false
        }
        switch dictationConfiguration.kind {
        case .globe:
            return keyCode == 179
        case .keyCombo:
            return UInt32(keyCode) == dictationConfiguration.keyCode
        }
    }

    private func releaseCancelShortcut() {
        removeOtherInputMonitor()
        if let hotKeyRef = carbonHotKeyRefs.removeValue(forKey: .cancel) {
            UnregisterEventHotKey(hotKeyRef)
        }
        // The cancel press itself ends the recording, which releases the
        // shortcut before its key-up arrives.
        heldSlots.remove(.cancel)
    }

    private func removeOtherInputMonitor() {
        if let otherInputMonitor {
            NSEvent.removeMonitor(otherInputMonitor)
            self.otherInputMonitor = nil
        }
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

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
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
        guard let globeSlot else {
            return
        }
        if event.type == .keyDown {
            if globeSlot == .dictation, heldSlots.contains(globeSlot), !isDictationShortcutKey(event.keyCode) {
                onHotkeyChord?()
            }
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

    func downCallback(for slot: Slot) -> (() -> Void)? {
        switch slot {
        case .dictation:
            return onHotkeyDown
        case .editMode:
            return onEditModeHotkeyDown
        case .pasteLastTranscript:
            // The recovery path may synthesize Command+V. Wait until the
            // physical shortcut key is released so the paste is not swallowed.
            return nil
        case .cancel:
            return onCancel
        }
    }

    func upCallback(for slot: Slot) -> (() -> Void)? {
        switch slot {
        case .dictation:
            return onHotkeyUp
        case .editMode:
            return onEditModeHotkeyUp
        case .pasteLastTranscript:
            return onPasteLastTranscript
        case .cancel:
            return nil
        }
    }
}
