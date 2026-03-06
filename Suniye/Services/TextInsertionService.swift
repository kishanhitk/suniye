import AppKit
import Foundation

final class TextInsertionService {
    enum InsertError: LocalizedError {
        case cannotCreateEvent

        var errorDescription: String? {
            switch self {
            case .cannotCreateEvent:
                return "Unable to generate keyboard event"
            }
        }
    }

    func insertText(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let clone = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    clone.setData(data, forType: type)
                }
            }
            return clone
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try postKey(9, flags: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            pasteboard.clearContents()
            pasteboard.writeObjects(previousItems)
        }
    }

    func submitActiveInput() throws {
        // Return key press submits in chat UIs.
        try postKey(36)
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw InsertError.cannotCreateEvent
        }

        down.flags = flags
        up.flags = flags

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
