import Foundation

struct ComputerUseScrollDelta: Equatable, Sendable {
    let horizontal: Double
    let vertical: Double
}

extension ComputerUseScrollDirection {
    /// Pixel units per "page" of scrolling in CGEvent pixel-unit scroll events.
    static let scrollPixelsPerPage: Double = 400

    /// Raw CGEvent convention: positive wheel1 scrolls up, positive wheel2
    /// scrolls left. Synthetic events bypass the natural-scrolling preference.
    func eventDelta(pages: Double) -> ComputerUseScrollDelta {
        let amount = pages * Self.scrollPixelsPerPage
        return switch self {
        case .up: ComputerUseScrollDelta(horizontal: 0, vertical: amount)
        case .down: ComputerUseScrollDelta(horizontal: 0, vertical: -amount)
        case .left: ComputerUseScrollDelta(horizontal: amount, vertical: 0)
        case .right: ComputerUseScrollDelta(horizontal: -amount, vertical: 0)
        }
    }
}

enum ComputerUseTypedTextEvent: Equatable, Sendable {
    case text(String)
    case returnKey
}

enum ComputerUseUnicodeEventChunker {
    static let maximumUTF16UnitsPerEvent = 20

    static func chunks(
        in text: String,
        maximumUTF16Units: Int = maximumUTF16UnitsPerEvent
    ) -> [String] {
        precondition(maximumUTF16Units > 0)
        var chunks: [String] = []
        var current = ""
        var currentLength = 0

        for character in text {
            let characterString = String(character)
            let characterLength = characterString.utf16.count
            if !current.isEmpty, currentLength + characterLength > maximumUTF16Units {
                chunks.append(current)
                current = ""
                currentLength = 0
            }
            current.append(character)
            currentLength += characterLength
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    /// Newlines become Return keystrokes so typed text can submit a form or send
    /// a message, which the tool contract promises. CR, LF, and CRLF each
    /// collapse to a single Return; text between newlines keeps the Unicode
    /// chunking path.
    static func typingEvents(
        in text: String,
        maximumUTF16Units: Int = maximumUTF16UnitsPerEvent
    ) -> [ComputerUseTypedTextEvent] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var events: [ComputerUseTypedTextEvent] = []
        for (index, line) in normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            if index > 0 {
                events.append(.returnKey)
            }
            for chunk in chunks(in: String(line), maximumUTF16Units: maximumUTF16Units) {
                events.append(.text(chunk))
            }
        }
        return events
    }
}
