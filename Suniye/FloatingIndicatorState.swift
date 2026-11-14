import AppKit

/// Presentation metrics shared by `FloatingIndicatorView` (pill + bubble) and
/// `FloatingIndicatorController` (hosting panel) so the two cannot drift.
enum FloatingIndicatorMetrics {
    /// A little more than two lines of tail text: the bubble shows the newest
    /// two lines and the older remainder fades out at the top, so keeping a
    /// third line's worth gives the fade something to act on.
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
    /// The bubble casts a soft shadow (radius 12, y-offset 4); the panel must
    /// reserve room around it or the window edge clips the shadow.
    static let previewShadowPadding: CGFloat = 16

    static func pillSize(source: FloatingIndicatorState.Source) -> CGSize {
        source == .editHotkey ? editModeListeningPillSize : listeningPillSize
    }

    /// The meeting pill, sized to what it shows. At rest: the dot, the time
    /// when it shows, then one level meter, or one glyph while paused or while
    /// a track has a problem. On hover: the dot, the time when it shows, and
    /// Pause (or Resume), Stop and Open Notes.
    static func meetingPillSize(expanded: Bool, isPaused: Bool, hasProblem: Bool, showsTime: Bool) -> CGSize {
        let lead = meetingPillDotWidth + (showsTime ? meetingPillGap + meetingPillTimeWidth : 0)
        guard expanded else {
            let trailing = isPaused || hasProblem ? meetingPillGlyphWidth : meetingPillMeterWidth
            return CGSize(width: 2 * 14 + lead + meetingPillGap + trailing, height: 34)
        }
        let buttons = meetingPillButtonWidth(isPaused ? "Resume" : "Pause", hasIcon: true)
            + meetingPillButtonWidth("Stop", hasIcon: true)
            + meetingPillButtonWidth("Open Notes", hasIcon: false)
        return CGSize(width: 2 * 11 + lead + 3 * meetingPillGap + buttons, height: 40)
    }

    static let meetingPillGap: CGFloat = 10
    static let meetingPillDotWidth: CGFloat = 8
    /// Five bars of 2 pt with 2 pt between them.
    static let meetingPillMeterWidth: CGFloat = 18
    static let meetingPillGlyphWidth: CGFloat = 14
    static let meetingPillIconWidth: CGFloat = 11
    static let meetingPillTimeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    static let meetingPillButtonFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    /// "0:00:00": the widest time of a recording, which stops at 4 hours.
    static let meetingPillTimeWidth = textWidth("0:00:00", font: meetingPillTimeFont)

    /// A capsule button of the hovered pill: 9 pt on each side, and the icon
    /// 5 pt before the title.
    static func meetingPillButtonWidth(_ title: String, hasIcon: Bool) -> CGFloat {
        9 + (hasIcon ? meetingPillIconWidth + 5 : 0) + textWidth(title, font: meetingPillButtonFont) + 9
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Room for the meeting's dot, and its time when it shows, in a
    /// listening pill. The dot alone takes its width and the pill's 10 pt gap.
    static func meetingLeadWidth(showsTime: Bool) -> CGFloat {
        showsTime ? 66 : meetingPillDotWidth + 10
    }

    /// Combined panel size. The panel is bottom-anchored and its content is
    /// bottom-aligned, so extra height for the bubble grows upward only and the
    /// pill stays put on screen. Bubble space is reserved as soon as previews
    /// are possible (`.pending`), not when the first partial lands — the panel
    /// must never resize mid-recording, or its AppKit frame animation races the
    /// SwiftUI bubble transition.
    static func listeningPanelSize(
        preview: FloatingIndicatorState.PreviewState,
        source: FloatingIndicatorState.Source = .hotkey,
        meetingLeadWidth: CGFloat = 0
    ) -> CGSize {
        var pillSize = pillSize(source: source)
        pillSize.width += meetingLeadWidth
        guard preview.reservesBubbleSpace else {
            return pillSize
        }
        return CGSize(
            width: max(pillSize.width, previewBubbleSize.width + previewShadowPadding * 2),
            height: pillSize.height + previewBubbleGap + previewBubbleSize.height + previewShadowPadding
        )
    }

    /// Tail of a partial transcript kept for the live-preview bubble. No
    /// ellipsis marker: the bubble fades older text out at the top instead, so
    /// a leading "…" would only double up with that fade.
    static func previewTail(_ text: String, maxCharacters: Int = previewTailMaxCharacters) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else {
            return trimmed
        }
        return String(trimmed.suffix(maxCharacters))
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

extension FloatingIndicatorMetrics {
    @MainActor
    static func meetingPillSize(for session: MeetingSession, expanded: Bool, showsTime: Bool) -> CGSize {
        meetingPillSize(expanded: expanded, isPaused: session.isPaused, hasProblem: session.hasTrackProblem, showsTime: showsTime)
    }
}
