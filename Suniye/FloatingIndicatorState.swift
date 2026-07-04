import CoreGraphics
import Foundation

/// Presentation metrics shared by `FloatingIndicatorView` (pill + bubble) and
/// `FloatingIndicatorController` (hosting panel) so the two cannot drift.
enum FloatingIndicatorMetrics {
    /// Two wrapped lines' worth of tail text in the fixed-width bubble.
    static let previewTailMaxCharacters = 160
    /// The newest characters render brighter than the rest so the eye tracks
    /// the growing tail, Apple-dictation style.
    static let previewBrightTailCharacters = 40
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
    /// The bubble casts a soft shadow (radius 12, y-offset 4); the panel must
    /// reserve room around it or the window edge clips the shadow.
    static let previewShadowPadding: CGFloat = 16

    static func pillSize(source: FloatingIndicatorState.Source) -> CGSize {
        source == .editHotkey ? editModeListeningPillSize : listeningPillSize
    }

    /// Combined panel size. The panel is bottom-anchored and its content is
    /// bottom-aligned, so extra height for the bubble grows upward only and the
    /// pill stays put on screen. Bubble space is reserved as soon as previews
    /// are possible (`.pending`), not when the first partial lands — the panel
    /// must never resize mid-recording, or its AppKit frame animation races the
    /// SwiftUI bubble transition.
    static func listeningPanelSize(
        preview: FloatingIndicatorState.PreviewState,
        source: FloatingIndicatorState.Source = .hotkey
    ) -> CGSize {
        let pillSize = pillSize(source: source)
        guard preview.reservesBubbleSpace else {
            return pillSize
        }
        return CGSize(
            width: max(pillSize.width, previewBubbleSize.width + previewShadowPadding * 2),
            height: pillSize.height + previewBubbleGap + previewBubbleSize.height + previewShadowPadding
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

    /// Splits preview text into a dimmed head and a bright tail (the newest
    /// characters). The split never lands mid-word: it extends left to the
    /// nearest word boundary so a word can't flicker between the two styles.
    static func previewSegments(
        _ text: String,
        brightTailCharacters: Int = previewBrightTailCharacters
    ) -> (head: String, tail: String) {
        guard text.count > brightTailCharacters else {
            return (head: "", tail: text)
        }
        var splitIndex = text.index(text.endIndex, offsetBy: -brightTailCharacters)
        if text[splitIndex] == " " {
            // Landed on a space: the tail starts at the next word.
            while splitIndex < text.endIndex, text[splitIndex] == " " {
                splitIndex = text.index(after: splitIndex)
            }
        } else {
            let headRange = text.startIndex ..< splitIndex
            if let boundary = text.range(of: " ", options: .backwards, range: headRange) {
                splitIndex = text.index(after: boundary.lowerBound)
            }
        }
        return (head: String(text[..<splitIndex]), tail: String(text[splitIndex...]))
    }
}

enum FloatingIndicatorState: Equatable {
    enum Source: String, Equatable {
        case hotkey
        case manual
        case editHotkey
    }

    /// Lifecycle of the live-preview bubble during a listening session.
    /// `.pending` means previews are active but nothing has decoded yet — the
    /// panel already reserves bubble space so it never resizes mid-recording.
    enum PreviewState: Equatable {
        case off
        case pending
        case text(String)

        var reservesBubbleSpace: Bool {
            self != .off
        }

        var text: String? {
            if case let .text(value) = self {
                return value
            }
            return nil
        }
    }

    case idle
    case hover
    case listening(levels: [Float], source: Source, preview: PreviewState = .off)
    case processing(message: String? = nil)
    case error(message: String)

    /// Reduced value for the pill's layout spring: changes only when the pill
    /// itself should animate (state shape, source, message). Per-tick churn —
    /// audio levels and preview text — is excluded so the spring doesn't
    /// re-fire on every meter update; the bubble animates via its own
    /// transition instead.
    var layoutAnimationKey: LayoutAnimationKey {
        switch self {
        case .idle:
            return .idle
        case .hover:
            return .hover
        case let .listening(_, source, _):
            return .listening(source: source)
        case let .processing(message):
            return .processing(message: message)
        case let .error(message):
            return .error(message: message)
        }
    }

    enum LayoutAnimationKey: Equatable {
        case idle
        case hover
        case listening(source: Source)
        case processing(message: String?)
        case error(message: String)
    }

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
