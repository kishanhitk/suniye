import CoreGraphics
import Foundation

/// Presentation metrics shared by `FloatingIndicatorView` (pill + bubble) and
/// `FloatingIndicatorController` (hosting panel) so the two cannot drift.
enum FloatingIndicatorMetrics {
    /// Two wrapped lines' worth of tail text in the fixed-width bubble.
    static let previewTailMaxCharacters = 160
    /// The listening pill never changes size; the live preview renders in a
    /// detached bubble floating above it.
    static let listeningPillSize = CGSize(width: 124, height: 40)
    /// Edit Mode prepends a pencil icon to the pill, so it is slightly wider.
    static let editModeListeningPillSize = CGSize(width: 150, height: 40)
    /// The bubble uses fixed geometry (two-line height reserved up front) so
    /// text length cannot jitter the layout; it appears once with the first
    /// partial and only the text content changes per tick. The bubble is
    /// source-independent: edit-mode instruction previews use the same bubble.
    static let previewBubbleSize = CGSize(width: 380, height: 56)
    static let previewBubbleGap: CGFloat = 8

    static func pillSize(source: FloatingIndicatorState.Source) -> CGSize {
        source == .editHotkey ? editModeListeningPillSize : listeningPillSize
    }

    /// Combined panel size. The panel is bottom-anchored and its content is
    /// bottom-aligned, so extra height for the bubble grows upward only and the
    /// pill stays put on screen.
    static func listeningPanelSize(preview: String?, source: FloatingIndicatorState.Source = .hotkey) -> CGSize {
        let pillSize = pillSize(source: source)
        guard preview != nil else {
            return pillSize
        }
        return CGSize(
            width: max(pillSize.width, previewBubbleSize.width),
            height: pillSize.height + previewBubbleGap + previewBubbleSize.height
        )
    }

    /// Tail of a partial transcript that fits the live-preview bubble.
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
