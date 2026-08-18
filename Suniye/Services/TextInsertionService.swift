import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

protocol TextInsertionServiceProtocol {
    func captureInsertionContext() -> TextInsertionContext?
    @MainActor @discardableResult func insertText(_ text: String) async throws -> InsertionOutcome
    func copyTextToClipboard(_ text: String) throws
    func submitActiveInput() throws
    func makeFocusedFieldValueProvider() -> (() -> String?)?
    func warmTargetAppAccessibility()
}

/// How an insertion reached the target, which decides whether the caller may
/// follow it with Return: only a paste we watched land in a known text element
/// is safe to submit.
enum InsertionOutcome: Equatable {
    /// A focused text element was visible and received the text.
    case intoFocusedElement
    /// The target app exposes no focused element at all, so the paste was
    /// posted without confirming what has focus (KIS-205).
    case unverified
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

    enum InsertError: LocalizedError {
        case cannotCreateEvent
        case cannotCopyToClipboard
        case noFocusedTextInput

        var errorDescription: String? {
            switch self {
            case .cannotCreateEvent:
                return "Unable to generate keyboard event"
            case .cannotCopyToClipboard:
                return "Unable to copy transcription to the clipboard"
            case .noFocusedTextInput:
                return "No editable text field is focused"
            }
        }
    }

    /// Why a focused text element was or was not found. The two failure cases
    /// are not the same thing and must not be treated alike: one says "that is
    /// not a text field", the other says "this app tells us nothing at all".
    enum FocusedElementLookup: Equatable {
        case found(AXUIElement)
        /// A real element has focus and it is not an editable text input.
        case notTextInput
        /// The app reports no focused element whatsoever. Chromium browsers
        /// keep their renderer accessibility tree switched off until a real
        /// assistive technology enables it, and answer `kAXErrorNoValue` for
        /// every focus query until then (KIS-205).
        case unavailable
    }

    var pasteboardProvider: () -> NSPasteboard = { .general }
    var accessibilityTrustProvider: () -> Bool = { AXIsProcessTrusted() }
    var focusedElementLookupProvider: (() -> FocusedElementLookup)?
    var focusedTextSnapshotProvider: ((AXUIElement) -> FocusedTextSnapshot?)?
    var selectedTextSetter: ((AXUIElement, String) -> Bool)?
    var keyPoster: ((CGKeyCode, CGEventFlags) throws -> Void)?
    var pasteKeyCodeProvider: (() -> CGKeyCode?)?
    var clipboardRestoreDelay: TimeInterval = 0.45
    var frontmostAppPIDProvider: () -> pid_t? = {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    var manualAccessibilitySetter: ((pid_t) -> Void)?
    var focusedElementRetryCount = 8
    var focusedElementRetryIntervalNanoseconds: UInt64 = 150_000_000

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

    @MainActor
    @discardableResult
    func insertText(_ text: String) async throws -> InsertionOutcome {
        let focusedElement: AXUIElement
        switch await focusedTextElementAwaitingHydration() {
        case .found(let element):
            focusedElement = element
        case .notTextInput:
            // Something that is not a text field has focus, so the paste would
            // land on an arbitrary control — and a presumed success would let
            // auto-submit post Return there. Fail before touching the
            // clipboard; ⌃⌘V recovers the text.
            throw InsertError.noFocusedTextInput
        case .unavailable:
            // The app publishes no focus information at all, so there is
            // nothing to inspect and nothing to protect against — refusing
            // here only guarantees the user gets no text. Paste blind and tell
            // the caller it was never verified, so Return is withheld.
            try pasteViaClipboard(text)
            return .unverified
        }

        let initialState = captureFocusedTextState(for: focusedElement)
        if let initialState,
           insertDirectlyIntoFocusedTextElement(
               text,
               focusedElement: focusedElement,
               initialState: initialState
           ) {
            return .intoFocusedElement
        }

        try pasteViaClipboard(text)
        return .intoFocusedElement
    }

    /// Puts the text on the clipboard, posts ⌘V, and restores the previous
    /// contents.
    ///
    /// Fire-and-forget by design: post-paste AX observation cannot tell a
    /// failed paste from a lazy accessibility surface (Electron composers read
    /// as nil, terminals read stale — KIS-178), so a posted paste is reported
    /// as success.
    @MainActor
    private func pasteViaClipboard(_ text: String) throws {
        let pasteboard = pasteboardProvider()
        let previousItems = Self.clipboardSnapshot(from: pasteboard.pasteboardItems ?? [])

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        scheduleClipboardRestore(previousItems, to: pasteboard)

        try postKey(pasteKeyCode(), flags: .maskCommand)
    }

    /// Electron hydrates its accessibility tree asynchronously after
    /// warmTargetAppAccessibility; a cold Electron app needs up to ~1s before
    /// the focused composer exists (KIS-181). Covers the paste-last path,
    /// which warms and inserts back to back.
    ///
    /// Retries cover both misses, because a hydrating app reports `unavailable`
    /// before its composer appears. An app that never hydrates keeps whatever
    /// it last reported, which is how a Chromium browser ends up `unavailable`.
    private func focusedTextElementAwaitingHydration() async -> FocusedElementLookup {
        var lastLookup = FocusedElementLookup.unavailable
        for attempt in 0 ..< max(focusedElementRetryCount, 1) {
            lastLookup = lookUpFocusedElement()
            if case .found = lastLookup {
                return lastLookup
            }
            if attempt < focusedElementRetryCount - 1 {
                try? await Task.sleep(nanoseconds: focusedElementRetryIntervalNanoseconds)
            }
        }
        return lastLookup
    }

    /// Electron/Chromium apps leave their accessibility tree unbuilt until a
    /// client opts in via AXManualAccessibility; a cold tree makes the focused
    /// composer invisible to getFocusedTextElement (KIS-181). Called when
    /// recording starts so the tree hydrates while the user speaks. Apps that
    /// do not support the attribute reject the write harmlessly.
    func warmTargetAppAccessibility() {
        guard let pid = frontmostAppPIDProvider() else { return }
        if let manualAccessibilitySetter {
            manualAccessibilitySetter(pid)
            return
        }
        // The AX write is a synchronous cross-process call with a multi-second
        // timeout when the target app hangs; keep it off the caller's (main)
        // thread so the hotkey flow never stalls.
        DispatchQueue.global(qos: .userInitiated).async {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
    }

    func copyTextToClipboard(_ text: String) throws {
        let pasteboard = pasteboardProvider()
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw InsertError.cannotCopyToClipboard
        }
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

    private func insertDirectlyIntoFocusedTextElement(
        _ text: String,
        focusedElement: AXUIElement,
        initialState: FocusedTextSnapshot
    ) -> Bool {
        guard setSelectedText(text, on: focusedElement),
              let currentState = captureFocusedTextState(for: focusedElement) else {
            return false
        }

        return Self.focusedTextDidChange(from: initialState, to: currentState)
    }

    private func getFocusedTextElement() -> AXUIElement? {
        guard case .found(let element) = lookUpFocusedElement() else {
            return nil
        }
        return element
    }

    /// Reads the system-wide focused element, separating "not a text field"
    /// from "this app answered with nothing".
    ///
    /// Every app that participates in accessibility answers this query with
    /// *some* element even when nothing text-like has focus — a bare desktop
    /// reports `AXGroup`, a file list reports `AXList`. Only an app whose
    /// accessibility tree is switched off returns no value at all, so that
    /// error is a reliable signal that inspection is impossible rather than
    /// that the target is unsuitable.
    private func lookUpFocusedElement() -> FocusedElementLookup {
        if let focusedElementLookupProvider {
            return focusedElementLookupProvider()
        }

        guard accessibilityTrustProvider() else {
            // Without the permission nothing can be read or posted, and the
            // caller surfaces its own permission prompt.
            return .notTextInput
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard status == .success, let focusedElement else {
            return status == .noValue ? .unavailable : .notTextInput
        }

        let element = focusedElement as! AXUIElement
        return Self.isTextInputElement(element) ? .found(element) : .notTextInput
    }

    static func isTextInputElement(_ element: AXUIElement) -> Bool {
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

    func setSelectedText(_ text: String, on element: AXUIElement) -> Bool {
        if let selectedTextSetter {
            return selectedTextSetter(element, text)
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    func captureFocusedTextState(for element: AXUIElement) -> FocusedTextSnapshot? {
        if let focusedTextSnapshotProvider {
            return focusedTextSnapshotProvider(element)
        }

        return (
            value: stringAttribute(kAXValueAttribute as CFString, from: element),
            selectedText: stringAttribute(kAXSelectedTextAttribute as CFString, from: element),
            selectedRange: selectedRangeAttribute(from: element)
        )
    }

    func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    func selectedRangeAttribute(from element: AXUIElement) -> NSRange? {
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

    static func virtualKeyCode(for character: String) -> CGKeyCode? {
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
