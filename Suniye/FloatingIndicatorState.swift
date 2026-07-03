import CoreGraphics
import Foundation

/// Presentation metrics shared by `FloatingIndicatorView` (pill) and
/// `FloatingIndicatorController` (hosting panel) so the two cannot drift.
enum FloatingIndicatorMetrics {
    static let previewTailMaxCharacters = 80

    static func listeningPillWidth(preview: String?) -> CGFloat {
        guard let preview else {
            return 124
        }
        return min(max(CGFloat(preview.count) * 6.5 + 96, 220), 460)
    }

    /// Tail of a partial transcript that fits the live-preview capsule.
    static func previewTail(_ text: String, maxCharacters: Int = previewTailMaxCharacters) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else {
            return trimmed
        }
        return "…" + String(trimmed.suffix(maxCharacters))
    }
}

enum FloatingIndicatorState: Equatable {
    enum Source: String, Equatable {
        case hotkey
        case manual
        case editHotkey
    }

    case idle
    case hover
    case listening(levels: [Float], source: Source, preview: String? = nil)
    case processing(message: String? = nil)
    case error(message: String)

    var logValue: String {
        switch self {
        case .idle:
            return "idle"
        case .hover:
            return "hover"
        case .listening:
            return "listening"
        case .processing:
            return "processing"
        case .error:
            return "error"
        }
    }

    var tracksPointerScreen: Bool {
        switch self {
        case .idle, .hover:
            return true
        case .listening, .processing, .error:
            return false
        }
    }
}
