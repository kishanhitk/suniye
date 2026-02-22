import AppKit

enum HotkeyTransition: Equatable {
    case none
    case pressed
    case released
}

struct HotkeyInputEvent {
    enum EventType {
        case keyDown
        case keyUp
        case flagsChanged
    }

    let type: EventType
    let keyCode: UInt16
    let modifiers: HotkeyShortcut.Modifiers
}

final class HotkeyStateMachine {
    private(set) var shortcut: HotkeyShortcut
    private(set) var pressedKeys: Set<UInt16> = []
    private(set) var currentModifiers: HotkeyShortcut.Modifiers = []
    private(set) var isShortcutHeld = false

    init(shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
    }

    func updateShortcut(_ shortcut: HotkeyShortcut) -> HotkeyTransition {
        self.shortcut = shortcut
        let isActive = shortcut.matches(modifiers: currentModifiers, pressedKeys: pressedKeys)
        if isShortcutHeld && !isActive {
            isShortcutHeld = false
            return .released
        }
        if !isShortcutHeld && isActive {
            isShortcutHeld = true
            return .pressed
        }
        return .none
    }

    func process(_ event: HotkeyInputEvent) -> HotkeyTransition {
        currentModifiers = event.modifiers

        switch event.type {
        case .keyDown:
            if !HotkeyShortcut.isModifierKeyCode(event.keyCode) {
                pressedKeys.insert(event.keyCode)
            }
        case .keyUp:
            pressedKeys.remove(event.keyCode)
        case .flagsChanged:
            break
        }

        let isActive = shortcut.matches(modifiers: currentModifiers, pressedKeys: pressedKeys)
        if isActive && !isShortcutHeld {
            isShortcutHeld = true
            return .pressed
        }
        if !isActive && isShortcutHeld {
            isShortcutHeld = false
            return .released
        }
        return .none
    }

    func reset() {
        pressedKeys.removeAll()
        currentModifiers = []
        isShortcutHeld = false
    }
}

final class HotkeyService {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var stateMachine = HotkeyStateMachine(shortcut: .defaultHoldToTalk)

    func startMonitoring(shortcut: HotkeyShortcut = .defaultHoldToTalk) {
        stopMonitoring()
        stateMachine = HotkeyStateMachine(shortcut: shortcut)

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    func updateShortcut(_ shortcut: HotkeyShortcut) {
        let transition = stateMachine.updateShortcut(shortcut)
        emit(transition)
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

        if stateMachine.isShortcutHeld {
            onHotkeyUp?()
        }
        stateMachine.reset()
    }

    deinit {
        stopMonitoring()
    }

    private func handle(event: NSEvent) {
        if event.type == .keyDown, event.isARepeat {
            return
        }

        let input = makeInputEvent(from: event)
        guard let input else {
            return
        }

        let transition = stateMachine.process(input)
        emit(transition)
    }

    private func emit(_ transition: HotkeyTransition) {
        switch transition {
        case .pressed:
            AppLogger.shared.log(.debug, "hotkey down shortcut=\(stateMachine.shortcut.displayText)")
            onHotkeyDown?()
        case .released:
            AppLogger.shared.log(.debug, "hotkey up shortcut=\(stateMachine.shortcut.displayText)")
            onHotkeyUp?()
        case .none:
            break
        }
    }

    private func makeInputEvent(from event: NSEvent) -> HotkeyInputEvent? {
        let modifiers = HotkeyShortcut.Modifiers.from(event.modifierFlags)

        switch event.type {
        case .flagsChanged:
            return HotkeyInputEvent(type: .flagsChanged, keyCode: event.keyCode, modifiers: modifiers)
        case .keyDown:
            return HotkeyInputEvent(type: .keyDown, keyCode: event.keyCode, modifiers: modifiers)
        case .keyUp:
            return HotkeyInputEvent(type: .keyUp, keyCode: event.keyCode, modifiers: modifiers)
        default:
            return nil
        }
    }
}
