import AppKit

/// Presentation metrics shared by `FloatingIndicatorView` (pill and accessories)
/// and `FloatingIndicatorController` (panel and anchor).
enum FloatingIndicatorMetrics {
    /// The panel never changes size and is centered on the idle bar's bottom
    /// center. It holds the widest content (the live preview bubble and its
    /// shadow) grown to either side of the idle bar, and the tallest stack
    /// above or below it. So neither a state change nor a change of the
    /// anchored edges moves or resizes the window: the pill only changes
    /// shape and alignment inside it.
    static let panelSize = CGSize(width: 736, height: 300)
    /// The idle bar's bottom center sits this far above the panel's bottom.
    static let anchorHeight: CGFloat = 147
    /// The widest thing the panel shows, for the edge check of the anchor.
    static let widestContent: CGFloat = previewBubbleSize.width
    /// The tallest stack: the bubble, its gap, and a two-line notice.
    static let tallestContent: CGFloat = previewBubbleSize.height + accessoryGap + 52

    static let idlePillSize = CGSize(width: 74, height: 7)
    static let hoverPillSize = CGSize(width: 152, height: 32)
    /// Listening and working share one pill, so the release of the shortcut
    /// changes what the dots do and nothing else.
    static let dictationPillSize = CGSize(width: 128, height: 32)
    /// While a stage message shows, the dots step aside to this width.
    static let compactFieldWidth: CGFloat = 40
    static let noticeMaxTextWidth: CGFloat = 300
    static let pillHeight: CGFloat = 32

    /// A little more than two lines of tail text: the bubble shows the newest
    /// two lines and the older remainder fades out at the top, so keeping a
    /// third line's worth gives the fade something to act on.
    static let previewTailMaxCharacters = 160
    /// The bubble uses fixed geometry (two-line height) so text length cannot
    /// jitter the layout; only the text changes per tick.
    static let previewBubbleSize = CGSize(width: 380, height: 56)
    static let accessoryGap: CGFloat = 8

    /// The meeting pill, sized to what it shows. At rest: the dot, the time
    /// when it shows, then one level meter, or one glyph while paused or while
    /// a track has a problem. On hover: the dot, the time when it shows, and
    /// Pause (or Resume), Stop and Open Notes.
    static func meetingPillSize(expanded: Bool, isPaused: Bool, hasProblem: Bool, showsTime: Bool) -> CGSize {
        let lead = meetingPillDotWidth + (showsTime ? meetingPillGap + meetingPillTimeWidth : 0)
        guard expanded else {
            let trailing = isPaused || hasProblem ? meetingPillGlyphWidth : meetingPillMeterWidth
            return CGSize(width: 2 * 14 + lead + meetingPillGap + trailing, height: pillHeight)
        }
        let buttons = meetingPillButtonWidth(isPaused ? "Resume" : "Pause", hasIcon: true)
            + meetingPillButtonWidth("Stop", hasIcon: true)
            + meetingPillButtonWidth("Open Notes", hasIcon: false)
        return CGSize(width: 2 * 11 + lead + 3 * meetingPillGap + buttons, height: 36)
    }

    static let meetingPillGap: CGFloat = 10
    static let meetingPillDotWidth: CGFloat = 8
    /// Five bars of 2 pt with 2 pt between them.
    static let meetingPillMeterWidth: CGFloat = 18
    static let meetingPillGlyphWidth: CGFloat = 14
    static let meetingPillIconWidth: CGFloat = 11
    static let meetingPillTimeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
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

/// Where the pill sits in its panel, and which way it grows. Away from the
/// screen edges the pill grows up and out from its bottom center. Near a side
/// edge it keeps the idle bar's outer edge and grows away from the edge; near
/// the top it hangs from the idle bar's top edge and its accessories go below.
struct FloatingIndicatorAnchor: Equatable {
    enum Horizontal: Equatable {
        case leading
        case center
        case trailing
    }

    enum Vertical: Equatable {
        /// The pill's bottom edge stays; accessories go above it.
        case bottom
        /// The pill's top edge stays; accessories go below it.
        case top
    }

    /// The idle bar's bottom center, in screen points.
    var point: CGPoint
    var horizontal: Horizontal = .center
    var vertical: Vertical = .bottom

    /// The fixed panel frame, centered on the anchor point whatever the edges.
    var panelFrame: NSRect {
        let size = FloatingIndicatorMetrics.panelSize
        return NSRect(
            x: (point.x - size.width / 2).rounded(),
            y: (point.y - FloatingIndicatorMetrics.anchorHeight).rounded(),
            width: size.width,
            height: size.height
        )
    }
}

enum FloatingIndicatorState: Equatable {
    enum Source: String, Equatable {
        case hotkey
        case manual
        case editHotkey
    }

    /// What the busy pill works on.
    enum ProcessingStep: Hashable {
        case transcribing
        case formatting
    }

    case idle
    case hover
    /// `preview` is the live transcript's tail, or nil before the first words
    /// and when the live preview is off.
    case listening(source: Source, preview: String? = nil)
    /// `message` shows only for a wait worth a word; the dots show the step.
    case processing(step: ProcessingStep = .transcribing, message: String? = nil)
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

    var isListening: Bool {
        if case .listening = self {
            return true
        }
        return false
    }

    /// No dictation runs: the pill follows the pointer's screen, can be
    /// dragged, and shows its hint on hover.
    var isAtRest: Bool {
        switch self {
        case .idle, .hover:
            return true
        case .listening, .processing, .error:
            return false
        }
    }

    /// A click starts a dictation (hover) or finishes one the pill started.
    var acceptsClicks: Bool {
        switch self {
        case .hover:
            return true
        case let .listening(source, _):
            return source == .manual
        case .idle, .processing, .error:
            return false
        }
    }

    func showsMeetingPill(hasMeeting: Bool) -> Bool {
        hasMeeting && isAtRest
    }

    func showsHoverHint(hasMeeting: Bool) -> Bool {
        self == .hover && !hasMeeting
    }
}

extension FloatingIndicatorMetrics {
    @MainActor
    static func meetingPillSize(for session: MeetingSession, expanded: Bool, showsTime: Bool) -> CGSize {
        meetingPillSize(expanded: expanded, isPaused: session.isPaused, hasProblem: session.hasTrackProblem, showsTime: showsTime)
    }
}
