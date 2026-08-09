import Foundation

struct ComputerUseScrollDelta: Equatable, Sendable {
    let horizontal: Double
    let vertical: Double
}

extension ComputerUseScrollDirection {
    func eventDelta(pages: Double) -> ComputerUseScrollDelta {
        let amount = pages * 400
        return switch self {
        case .up: ComputerUseScrollDelta(horizontal: 0, vertical: -amount)
        case .down: ComputerUseScrollDelta(horizontal: 0, vertical: amount)
        case .left: ComputerUseScrollDelta(horizontal: -amount, vertical: 0)
        case .right: ComputerUseScrollDelta(horizontal: amount, vertical: 0)
        }
    }
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
}
