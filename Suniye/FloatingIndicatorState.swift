import CoreGraphics
import Foundation

/// Presentation metrics shared by `FloatingIndicatorView` (pill) and
/// `FloatingIndicatorController` (hosting panel) so the two cannot drift.
enum FloatingIndicatorMetrics {
    /// Two wrapped lines' worth of tail text in the fixed-width capsule.
    static let previewTailMaxCharacters = 160
    /// The preview capsule uses fixed geometry: it expands once when the first
    /// partial appears and never resizes per tick, so text length cannot jitter
    /// the pill. Height reserves two wrapped lines up front.
    static let previewCapsuleWidth: CGFloat = 380
    static let previewCapsuleHeight: CGFloat = 64

    static func listeningPillWidth(preview: String?) -> CGFloat {
        preview == nil ? 124 : previewCapsuleWidth
    }

    static func listeningPillHeight(preview: String?) -> CGFloat {
        preview == nil ? 40 : previewCapsuleHeight
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
