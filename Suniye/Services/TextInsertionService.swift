import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

protocol TextInsertionServiceProtocol {
    func captureInsertionContext() -> TextInsertionContext?
    func insertText(_ text: String) throws
    func submitActiveInput() throws
    func makeFocusedFieldValueProvider() -> (() -> String?)?
}

struct TextInsertionContext: Equatable {
    let value: String
    let selectedRange: NSRange
    let selectedText: String?
    let previousCharacter: Character?
    let nextCharacter: Character?
}

final class TextInsertionService: TextInsertionServiceProtocol {
    typealias ClipboardItemSnapshot = [NSPasteboard.PasteboardType: Data]
    typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    typealias FocusedTextSnapshot = (value: String?, selectedText: String?, selectedRange: NSRange?)

    enum InsertError: LocalizedError, Equatable {
        case cannotCreateEvent
        case secureFieldUnsupported

        var errorDescription: String? {
            switch self {
            case .cannotCreateEvent:
                return "Unable to generate keyboard event"
            case .secureFieldUnsupported:
                return "Cannot insert dictated text into a secure field"
            }
        }
    }

    /// Fallback used when verified Accessibility insertion is not available.
    enum InsertionStrategy: Equatable {
        /// Stage text on the clipboard and paste with Cmd+V. Default.
        case clipboardPaste
        /// Synthesize the text as keyboard input via CGEvent Unicode. Never touches
        /// the clipboard; for apps where AX and paste are unreliable (remote
        /// desktops, terminals, some Electron/web areas).
        case keyboardTypeOut
    }

    var pasteboardProvider: () -> NSPasteboard = { .general }
    var focusedTextElementProvider: (() -> AXUIElement?)?
    var focusedTextSnapshotProvider: ((AXUIElement) -> FocusedTextSnapshot?)?
    var selectedTextSetter: ((AXUIElement, String) -> Bool)?
    var keyPoster: ((CGKeyCode, CGEventFlags) throws -> Void)?
    var pasteKeyCodeProvider: (() -> CGKeyCode?)?
    var clipboardRestoreDelay: TimeInterval = 0.45
    /// Resolves the fallback strategy per insertion (e.g. from the frontmost app).
    /// Defaults to `.clipboardPaste` when unset, preserving prior behavior.
    var insertionStrategyProvider: (() -> InsertionStrategy)?
    /// Injection seam for keyboard type-out (mirrors `keyPoster`).
    var unicodeTyper: ((String) throws -> Void)?
    /// Injection seam for reading a pasteboard's change count (default reads live).
    var clipboardChangeCountProvider: ((NSPasteboard) -> Int)?
    /// Injection seam for secure-field detection (default reads the focused element).
    var secureFieldDetector: (() -> Bool)?

    func captureInsertionContext() -> TextInsertionContext? {
        guard let focusedElement = getFocusedTextElement(),
              let state = captureFocusedTextState(for: focusedElement),
              let value = state.value,
              let selectedRange = state.selectedRange,
              let stringRange = Range(selectedRange, in: value) else {
            return nil
        }

        let previousCharacter = stringRange.lowerBound > value.startIndex
            ? value[value.index(before: stringRange.lowerBound)]
            : nil
        let nextCharacter = stringRange.upperBound < value.endIndex
            ? value[stringRange.upperBound]
            : nil

        return TextInsertionContext(
            value: value,
            selectedRange: selectedRange,
            selectedText: state.selectedText,
            previousCharacter: previousCharacter,
            nextCharacter: nextCharacter
        )
    }

    /// Captures the currently focused text element and returns a closure that
    /// re-reads its value later, so edit learning can diff the same field the
    /// dictation was inserted into. Returns nil when no AX-readable field is focused.
    func makeFocusedFieldValueProvider() -> (() -> String?)? {
        guard let focusedElement = getFocusedTextElement() else {
            return nil
        }
        return { [weak self] in
            self?.captureFocusedTextState(for: focusedElement)?.value
        }
    }

    func insertText(_ text: String) throws {
        // Tier 0: never stage or type a transcription into a secure (password) field.
        if isFocusedFieldSecure() {
            AppLogger.shared.log(.warning, "text insertion skipped: focused field is secure")
            throw InsertError.secureFieldUnsupported
        }

        // Tier 1: verified Accessibility value insertion (clipboard-free, preferred).
        if insertDirectlyIntoFocusedTextElement(text) {
            return
        }

        // Tier 2/3: fallback chosen per app.
        switch insertionStrategyProvider?() ?? .clipboardPaste {
        case .clipboardPaste:
            try pasteViaClipboard(text)
        case .keyboardTypeOut:
            try typeOut(text)
        }
    }

    private func pasteViaClipboard(_ text: String) throws {
        let pasteboard = pasteboardProvider()
        let previousItems = Self.clipboardSnapshot(from: pasteboard.pasteboardItems ?? [])

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let stampedChangeCount = changeCount(of: pasteboard)

        // Scheduled before posting the paste key so a throw from postKey still restores.
        scheduleClipboardRestore(previousItems, to: pasteboard, expectedChangeCount: stampedChangeCount)

        try postKey(pasteKeyCode(), flags: .maskCommand)
    }

    private func changeCount(of pasteboard: NSPasteboard) -> Int {
        clipboardChangeCountProvider?(pasteboard) ?? pasteboard.changeCount
    }

    private func scheduleClipboardRestore(
        _ previousItems: ClipboardSnapshot,
        to pasteboard: NSPasteboard,
        expectedChangeCount: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) { [weak self] in
            guard let self else { return }
            // Cmd+V reads the pasteboard (no changeCount bump); a user Cmd+C writes to
            // it (bump). If the count moved, someone else owns the clipboard now — do
            // not clobber their copy.
            let current = self.changeCount(of: pasteboard)
            guard current == expectedChangeCount else {
                AppLogger.shared.log(.info, "clipboard restore skipped: changeCount \(expectedChangeCount)->\(current)")
                return
            }
            pasteboard.clearContents()
            pasteboard.writeObjects(Self.pasteboardItems(from: previousItems))
        }
    }

    private func typeOut(_ text: String) throws {
        if let unicodeTyper {
            try unicodeTyper(text)
            return
        }
        for chunk in Self.unicodeChunks(for: text, maxChunkUTF16: 20) {
            try postUnicodeChunk(chunk)
        }
    }

    private func postUnicodeChunk(_ chunk: [UniChar]) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            throw InsertError.cannotCreateEvent
        }
        chunk.withUnsafeBufferPointer { buffer in
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Splits `text` into UTF-16 chunks no larger than `maxChunkUTF16`, never
    /// splitting a Swift `Character`, so a surrogate pair / grapheme cluster is never
    /// broken across CGEvent buffers.
    static func unicodeChunks(for text: String, maxChunkUTF16: Int) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty, current.count + units.count > maxChunkUTF16 {
                chunks.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
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

        guard let element = copyFocusedElement(), Self.isTextInputElement(element) else {
            return nil
        }
        return element
    }

    /// Copies the system-wide focused UI element of any role, or nil when
    /// Accessibility is untrusted or nothing focused. The force-cast is guarded by
    /// an explicit `AXUIElement` type-ID check (the idiomatic pattern for CF types).
    private func copyFocusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focusedElement as! AXUIElement)
    }

    /// True when the focused field is a secure/password field. Uses the injected
    /// detector when present, otherwise reads the focused element's role/subrole.
    private func isFocusedFieldSecure() -> Bool {
        if let secureFieldDetector {
            return secureFieldDetector()
        }
        guard let element = copyFocusedElement() else {
            return false
        }
        return Self.isSecureTextElement(element)
    }

    private static func isSecureTextElement(_ element: AXUIElement) -> Bool {
        var roleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           (roleValue as? String) == "AXSecureTextField" {
            return true
        }
        var subroleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           (subroleValue as? String) == (kAXSecureTextFieldSubrole as String) {
            return true
        }
        return false
    }

    private static func isTextInputElement(_ element: AXUIElement) -> Bool {
        // Never AX-write into a secure field, even if a new editable role slips in below.
        if isSecureTextElement(element) {
            return false
        }

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

enum DictationInsertionTextFormatter {
    static func textForInsertion(
        _ text: String,
        insertionContext: TextInsertionContext?
    ) -> String {
        guard let insertionContext else {
            return text
        }

        var result = text
        if isHighConfidenceMidSentenceInsertion(insertionContext) {
            result = lowercasingFirstWordIfSafe(result)
        }
        if shouldStripFinalPeriod(insertionContext) {
            result = strippingSingleFinalPeriod(result)
        }

        if let previous = insertionContext.previousCharacter,
           let first = result.first,
           shouldInsertSpace(between: previous, and: first) {
            result = " " + result
        }

        if let next = insertionContext.nextCharacter,
           let last = result.last,
           shouldInsertSpace(between: last, and: next) {
            result += " "
        }

        return result
    }

    private static func isHighConfidenceMidSentenceInsertion(_ context: TextInsertionContext) -> Bool {
        guard let previous = context.previousCharacter else { return false }
        return isWordLike(previous)
    }

    private static func shouldStripFinalPeriod(_ context: TextInsertionContext) -> Bool {
        guard isHighConfidenceMidSentenceInsertion(context),
              let next = context.nextCharacter else {
            return false
        }
        return isWordLike(next)
    }

    private static func lowercasingFirstWordIfSafe(_ text: String) -> String {
        var result = text
        guard let wordRange = firstWordRange(in: result),
              shouldLowercaseFirstWord(String(result[wordRange])) else {
            return result
        }

        let firstIndex = wordRange.lowerBound
        let nextIndex = result.index(after: firstIndex)
        result.replaceSubrange(firstIndex..<nextIndex, with: String(result[firstIndex]).lowercased())
        return result
    }

    private static func firstWordRange(in text: String) -> Range<String.Index>? {
        var start = text.startIndex
        while start < text.endIndex, isWhitespace(text[start]) {
            start = text.index(after: start)
        }
        guard start < text.endIndex, isWordLike(text[start]) else {
            return nil
        }

        var end = text.index(after: start)
        while end < text.endIndex, isWordLike(text[end]) {
            end = text.index(after: end)
        }
        return start..<end
    }

    private static func shouldLowercaseFirstWord(_ word: String) -> Bool {
        guard word.count > 1,
              let first = word.first,
              isUppercaseLetter(first) else {
            return false
        }

        let remainder = word.dropFirst()
        guard remainder.contains(where: isLowercaseLetter) else {
            return false
        }
        return !remainder.contains(where: isUppercaseLetter)
    }

    private static func strippingSingleFinalPeriod(_ text: String) -> String {
        var result = text
        var currentIndex = result.endIndex

        while currentIndex > result.startIndex {
            let previousIndex = result.index(before: currentIndex)
            if isWhitespace(result[previousIndex]) {
                currentIndex = previousIndex
                continue
            }

            guard result[previousIndex] == "." else {
                return result
            }
            if previousIndex > result.startIndex {
                let beforePeriod = result.index(before: previousIndex)
                guard result[beforePeriod] != "." else {
                    return result
                }
            }
            result.removeSubrange(previousIndex..<currentIndex)
            return result
        }

        return result
    }

    private static func shouldInsertSpace(between left: Character, and right: Character) -> Bool {
        if isWhitespace(left) || isWhitespace(right) {
            return false
        }
        if closingPunctuation.contains(right) || openingPunctuation.contains(left) {
            return false
        }
        if isWordLike(left) && isWordLike(right) {
            return true
        }
        if isWordLike(right) && punctuationThatTakesFollowingSpace.contains(left) {
            return true
        }
        return false
    }

    private static let openingPunctuation: Set<Character> = ["(", "[", "{", "\"", "'"]
    private static let closingPunctuation: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}", "\"", "'"]
    private static let punctuationThatTakesFollowingSpace: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}", "\"", "'"]

    private static func isWordLike(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
    }

    private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
    }
}
