import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

protocol TextInsertionServiceProtocol {
    func insertText(_ text: String) throws
    func submitActiveInput() throws
}

final class TextInsertionService: TextInsertionServiceProtocol {
    typealias ClipboardItemSnapshot = [NSPasteboard.PasteboardType: Data]
    typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    typealias FocusedTextSnapshot = (value: String?, selectedText: String?, selectedRange: NSRange?)

    enum InsertError: LocalizedError {
        case cannotCreateEvent

        var errorDescription: String? {
            switch self {
            case .cannotCreateEvent:
                return "Unable to generate keyboard event"
            }
        }
    }

    var pasteboardProvider: () -> NSPasteboard = { .general }
    var focusedTextElementProvider: (() -> AXUIElement?)?
    var focusedTextSnapshotProvider: ((AXUIElement) -> FocusedTextSnapshot?)?
    var selectedTextSetter: ((AXUIElement, String) -> Bool)?
    var keyPoster: ((CGKeyCode, CGEventFlags) throws -> Void)?
    var pasteKeyCodeProvider: (() -> CGKeyCode?)?
    var clipboardRestoreDelay: TimeInterval = 0.45

    func insertText(_ text: String) throws {
        if insertDirectlyIntoFocusedTextElement(text) {
            return
        }

        let pasteboard = pasteboardProvider()
        let previousItems = Self.clipboardSnapshot(from: pasteboard.pasteboardItems ?? [])

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        scheduleClipboardRestore(previousItems, to: pasteboard)

        try postKey(pasteKeyCode(), flags: .maskCommand)
    }

    private func scheduleClipboardRestore(_ previousItems: ClipboardSnapshot, to pasteboard: NSPasteboard) {
        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
            pasteboard.clearContents()
            pasteboard.writeObjects(Self.pasteboardItems(from: previousItems))
        }
    }

    func submitActiveInput() throws {
        // Return key press submits in chat UIs.
        try postKey(36)
    }

    private func insertDirectlyIntoFocusedTextElement(_ text: String) -> Bool {
        guard let focusedElement = getFocusedTextElement(),
              let initialState = captureFocusedTextState(for: focusedElement),
              setSelectedText(text, on: focusedElement),
              let currentState = captureFocusedTextState(for: focusedElement) else {
            return false
        }

        return Self.focusedTextDidChange(from: initialState, to: currentState)
    }

    private func getFocusedTextElement() -> AXUIElement? {
        if let focusedTextElementProvider {
            return focusedTextElementProvider()
        }

        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            return nil
        }

        let element = focusedElement as! AXUIElement
        guard Self.isTextInputElement(element) else {
            return nil
        }

        return element
    }

    private static func isTextInputElement(_ element: AXUIElement) -> Bool {
        var roleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else {
            return false
        }

        // AXWebArea is a web document root, not an editable text input; setting selected text on it is invalid.
        return [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField",
        ].contains(role)
    }

    private func setSelectedText(_ text: String, on element: AXUIElement) -> Bool {
        if let selectedTextSetter {
            return selectedTextSetter(element, text)
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private func captureFocusedTextState(for element: AXUIElement) -> FocusedTextSnapshot? {
        if let focusedTextSnapshotProvider {
            return focusedTextSnapshotProvider(element)
        }

        return (
            value: stringAttribute(kAXValueAttribute as CFString, from: element),
            selectedText: stringAttribute(kAXSelectedTextAttribute as CFString, from: element),
            selectedRange: selectedRangeAttribute(from: element)
        )
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func selectedRangeAttribute(from element: AXUIElement) -> NSRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let rangeValue = value,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    private static func focusedTextDidChange(from initialState: FocusedTextSnapshot, to currentState: FocusedTextSnapshot) -> Bool {
        initialState.value != currentState.value
            || initialState.selectedText != currentState.selectedText
            || initialState.selectedRange != currentState.selectedRange
    }

    private func pasteKeyCode() -> CGKeyCode {
        pasteKeyCodeProvider?()
            ?? Self.virtualKeyCode(for: "v")
            ?? 9
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) throws {
        if let keyPoster {
            try keyPoster(keyCode, flags)
            return
        }

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw InsertError.cannotCreateEvent
        }

        down.flags = flags
        up.flags = flags

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func clipboardSnapshot(from items: [NSPasteboardItem]) -> ClipboardSnapshot {
        items.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                guard let data = item.data(forType: type) else {
                    return nil
                }
                return (type, data)
            })
        }
    }

    static func pasteboardItems(from snapshot: ClipboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }

    private static func virtualKeyCode(for character: String) -> CGKeyCode? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        for keyCode in UInt16(0) ... UInt16(127) {
            deadKeyState = 0
            let status = UCKeyTranslate(
                keyLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else {
                continue
            }
            if String(utf16CodeUnits: chars, count: length) == character {
                return CGKeyCode(keyCode)
            }
        }

        return nil
    }
}
