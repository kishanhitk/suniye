import AppKit
import Foundation

final class TextInsertionService {
    enum InsertError: LocalizedError {
        case cannotCreateEvent

        var errorDescription: String? {
            switch self {
            case .cannotCreateEvent:
                return "Unable to generate keyboard event for paste"
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

        try postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            pasteboard.clearContents()
            pasteboard.writeObjects(previousItems)
        }
    }

    private func postCommandV() throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            throw InsertError.cannotCreateEvent
        }

        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
