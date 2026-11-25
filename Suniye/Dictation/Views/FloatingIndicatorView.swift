import AppKit
import Observation
import SwiftUI

/// Observable state feeding the floating indicator. The controller mutates it
/// in place, so SwiftUI animates every change from what is on screen now.
@MainActor
@Observable
final class FloatingIndicatorModel {
    var state: FloatingIndicatorState = .idle
    var meeting: MeetingSession?
    var showsMeetingTime = true
    var hidesWhenIdle = false
    var horizontal: FloatingIndicatorAnchor.Horizontal = .center
    var vertical: FloatingIndicatorAnchor.Vertical = .bottom
    /// The system's Reduce Motion, read by the controller for the window and
    /// by the view for the pill and the dots, so all three always agree.
    var reduceMotion = false
    /// Written at the capture rate and read once a frame by the dots, outside
    /// observation, so the voice never re-renders the indicator.
    @ObservationIgnored let voice = DotScopeVoice()
}

enum MeetingPillAction {
    case open
    case pause
    case resume
    case stop
}

/// The indicator's one motion vocabulary.
enum FloatingIndicatorMotion {
        static let morph = Animation.spring(duration: 0.3, bounce: 0.15)
    /// With Reduce Motion the pill and its accessories cross-fade in place.
    static let reducedFade = Animation.easeInOut(duration: 0.16)
    /// Leaving is faster than arriving.
    static let exit = Animation.easeOut(duration: 0.12)
}

/// The pill's colors in the app's light or dark appearance. Text is quiet:
/// regular weight at reduced contrast, so the pill reports state without
/// pulling the eye from the user's work.
struct PillTheme {
    /// Inside the glass of active pills and the hint, so the dots and the text
    /// stay legible over any desktop.
    let plate: Color
    /// The glass tint of active pills; much lighter than the plate so the
    /// material shows through.
    let glassTint: Color
    /// macOS 14 and 15 draw this solid capsule instead of the glass.
    let fill: Color
    let stroke: Color
    let idleFill: Color
    let idleGlassTint: Color
    let idleStroke: Color
    /// Status text, notices and the hint.
    let text: Color
    /// The live preview: the user's own words, so a little brighter.
    let previewText: Color
    let icon: Color
    let mutedIcon: Color
    let restDot: Color
    let buttonWash: Color
    let previewMaterial: NSVisualEffectView.Material
    let previewWash: Color
    let shadow: Color
    let dots: DotScopePalette
    let editDots: DotScopePalette

    static let textFont = Font.subheadline

    static let dark = PillTheme(
        plate: .black.opacity(0.62),
        glassTint: .black.opacity(0.55),
        fill: .black.opacity(0.96),
        stroke: .white.opacity(0.14),
        idleFill: .black.opacity(0.58),
        idleGlassTint: .black.opacity(0.35),
        idleStroke: .white.opacity(0.34),
        text: .white.opacity(0.7),
        previewText: .white.opacity(0.84),
        icon: .white.opacity(0.8),
        mutedIcon: .white.opacity(0.5),
        restDot: .white.opacity(0.6),
        buttonWash: .white.opacity(0.12),
        previewMaterial: .hudWindow,
        previewWash: .black.opacity(0.35),
        shadow: .black.opacity(0.25),
        dots: .dictation,
        editDots: .edit
    )

    static let light = PillTheme(
        plate: .white.opacity(0.7),
        glassTint: .white.opacity(0.5),
        fill: Color(white: 0.97).opacity(0.97),
        stroke: .black.opacity(0.08),
        idleFill: .white.opacity(0.8),
        idleGlassTint: .white.opacity(0.4),
        idleStroke: .black.opacity(0.22),
        text: .black.opacity(0.6),
        previewText: .black.opacity(0.78),
        icon: .black.opacity(0.65),
        mutedIcon: .black.opacity(0.4),
        restDot: .black.opacity(0.4),
        buttonWash: .black.opacity(0.06),
        previewMaterial: .popover,
        previewWash: .white.opacity(0.35),
        shadow: .black.opacity(0.12),
        dots: .dictationLight,
        editDots: .editLight
    )

    func dots(edit: Bool) -> DotScopePalette {
        edit ? editDots : dots
    }
}

private struct PillThemeKey: EnvironmentKey {
    static let defaultValue = PillTheme.dark
}

extension EnvironmentValues {
    var pillTheme: PillTheme {
        get { self[PillThemeKey.self] }
        set { self[PillThemeKey.self] = newValue }
    }
}

struct FloatingIndicatorView: View {
    let model: FloatingIndicatorModel
    let onHoverChanged: (Bool) -> Void
    let onAction: () -> Void
    let onMeetingAction: (MeetingPillAction) -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void
    /// True while a drag of the pill is in flight. It resets however the
    /// gesture ends, also when SwiftUI cancels it, so the controller always
    /// hears that a drag ended.
    @GestureState private var isDragging = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: PillTheme { colorScheme == .dark ? .dark : .light }

    private var state: FloatingIndicatorState { model.state }
    private var reduceMotion: Bool { model.reduceMotion }

    var body: some View {
        VStack(alignment: stackAlignment, spacing: FloatingIndicatorMetrics.accessoryGap) {
            if model.vertical == .bottom {
                accessory
            }
            pill
            if model.vertical == .top {
                accessory
            }
        }
        .padding(edgeInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelAlignment)
        .animation(reduceMotion ? FloatingIndicatorMotion.reducedFade : FloatingIndicatorMotion.morph, value: appearance)
        .onChange(of: isDragging) { _, dragging in
            if !dragging {
                onDragEnded()
            }
        }
        .environment(\.pillTheme, theme)
    }

    // MARK: - What changes shape

    /// What the pill shows, with only what gives it its shape. The voice, the
    /// preview's words and the meeting's clock are left out, so the spring
    /// runs once for each real change and never per tick. With Reduce Motion
    /// a new shape is a new pill: a cross-fade instead of a morph.
    private enum PillShape: Hashable {
        case hidden
        case idle
        case hover
        case meeting(expanded: Bool, paused: Bool, problem: Bool, showsTime: Bool)
        /// Listening and working. `meetingTime` is set while a meeting
        /// records: whether its time shows beside the dots.
        case dictation(edit: Bool, message: String?, meetingTime: Bool?)
        case notice(String)
    }

    private struct Appearance: Equatable {
        var shape: PillShape
        var showsPreview: Bool
        var showsHint: Bool
        var horizontal: FloatingIndicatorAnchor.Horizontal
        var vertical: FloatingIndicatorAnchor.Vertical
    }

    private var pillShape: PillShape {
        if let meeting = model.meeting, state.showsMeetingPill(hasMeeting: true) {
            let expanded = state == .hover
            return .meeting(
                expanded: expanded,
                paused: meeting.isPaused,
                // The warning glyph shows only at rest and not paused.
                problem: !expanded && !meeting.isPaused && meeting.hasTrackProblem,
                showsTime: model.showsMeetingTime
            )
        }
        let meetingTime = model.meeting == nil ? nil : model.showsMeetingTime
        switch state {
        case .idle:
            return model.hidesWhenIdle ? .hidden : .idle
        case .hover:
            return .hover
        case let .listening(source, _):
            return .dictation(edit: source == .editHotkey, message: nil, meetingTime: meetingTime)
        case let .processing(_, message):
            return .dictation(edit: false, message: message, meetingTime: meetingTime)
        case let .error(message):
            return .notice(message)
        }
    }

    private var appearance: Appearance {
        Appearance(
            shape: pillShape,
            showsPreview: previewText != nil,
            showsHint: helperText != nil,
            horizontal: model.horizontal,
            vertical: model.vertical
        )
    }

    // MARK: - Layout in the fixed panel

    private var stackAlignment: HorizontalAlignment {
        switch model.horizontal {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var panelAlignment: Alignment {
        switch (model.horizontal, model.vertical) {
        case (.leading, .bottom): return .bottomLeading
        case (.center, .bottom): return .bottom
        case (.trailing, .bottom): return .bottomTrailing
        case (.leading, .top): return .topLeading
        case (.center, .top): return .top
        case (.trailing, .top): return .topTrailing
        }
    }

    /// Puts the idle bar on the anchor point at the panel's center line, for
    /// every choice of edges, so a change of edges never moves the idle bar.
    private var edgeInsets: EdgeInsets {
        let panel = FloatingIndicatorMetrics.panelSize
        let idle = FloatingIndicatorMetrics.idlePillSize
        let side = panel.width / 2 - idle.width / 2
        let below = FloatingIndicatorMetrics.anchorHeight
        let above = panel.height - below - idle.height
        return EdgeInsets(
            top: model.vertical == .top ? above : 0,
            leading: model.horizontal == .leading ? side : 0,
            bottom: model.vertical == .bottom ? below : 0,
            trailing: model.horizontal == .trailing ? side : 0
        )
    }

    /// The pill's anchored edge: the point it grows from, and the point its
    /// hint or bubble rises out of.
    private var growthAnchor: UnitPoint {
        let x: CGFloat
        switch model.horizontal {
        case .leading: x = 0
        case .center: x = 0.5
        case .trailing: x = 1
        }
        return UnitPoint(x: x, y: model.vertical == .bottom ? 1 : 0)
    }

    // MARK: - Transitions

    /// The pill materializes from its anchored edge, never from nothing.
    private var pillTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: growthAnchor))
    }

    /// Content inside the pill cross-fades with a light blur, so two states
    /// read as one object changing rather than two objects swapping.
    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: SoftFade(amount: 1), identity: SoftFade(amount: 0)),
            removal: .modifier(active: SoftFade(amount: 1), identity: SoftFade(amount: 0))
                .animation(FloatingIndicatorMotion.exit)
        )
    }

    private var accessoryTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let rise: CGFloat = model.vertical == .bottom ? 6 : -6
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.96, anchor: growthAnchor))
                .combined(with: .offset(y: rise)),
            removal: .opacity.animation(FloatingIndicatorMotion.exit)
        )
    }

    // MARK: - Accessories

    @ViewBuilder
    private var accessory: some View {
        if let helperText {
            Text(numbers: helperText)
                .font(PillTheme.textFont)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                // Static hint text — no `.interactive()` (the tap lives
                // on the pill below, not here).
                .liquidGlassPill(
                    fill: theme.fill,
                    plate: theme.plate,
                    glassTint: theme.glassTint,
                    stroke: theme.stroke,
                    strokeWidth: 1,
                    interactive: false
                )
                .onHover(perform: onHoverChanged)
                .transition(accessoryTransition)
        } else if let previewText {
            previewBubble(previewText)
                .transition(accessoryTransition)
        }
    }

    private static let previewBubbleShape = RoundedRectangle(
        cornerRadius: FloatingIndicatorMetrics.previewBubbleSize.height / 2,
        style: .continuous
    )

    /// Detached live-preview bubble beside the pill. Fixed geometry so only
    /// the text changes per tick, and non-interactive so the pill keeps all
    /// click and drag behavior.
    private func previewBubble(_ text: String) -> some View {
        LivePreviewText(text: text)
            .padding(.horizontal, 20)
            .frame(
                width: FloatingIndicatorMetrics.previewBubbleSize.width,
                height: FloatingIndicatorMetrics.previewBubbleSize.height,
                alignment: .leading
            )
            .background {
                ZStack {
                    BehindWindowBlur(
                        material: theme.previewMaterial,
                        state: .active,
                        cornerRadius: FloatingIndicatorMetrics.previewBubbleSize.height / 2
                    )
                    theme.previewWash
                }
            }
            .overlay(Self.previewBubbleShape.stroke(theme.stroke, lineWidth: 1))
            .clipShape(Self.previewBubbleShape)
            .shadow(color: theme.shadow, radius: 12, y: 4)
            .allowsHitTesting(false)
    }

    private var previewText: String? {
        if case let .listening(_, preview) = state {
            return preview
        }
        return nil
    }

    private var helperText: String? {
        state.showsHoverHint(hasMeeting: model.meeting != nil) ? "Click or hold fn to start dictating" : nil
    }

    // MARK: - Pill

    @ViewBuilder
    private var pill: some View {
        let shape = pillShape
        if shape != .hidden {
            ZStack {
                pillSurface(shape)
                    // With Reduce Motion each shape is its own pill, so a
                    // change cross-fades instead of morphing.
                    .id(reduceMotion ? AnyHashable(shape) : AnyHashable(0))
                    .transition(.opacity)
            }
            // Hover, tap and drag live outside the surface that Reduce Motion
            // swaps, so a swap never cancels them.
            .contentShape(Capsule())
            .onHover(perform: onHoverChanged)
            .onTapGesture {
                if case .meeting = shape {
                    onMeetingAction(.open)
                } else if isInteractive {
                    onAction()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .updating($isDragging) { _, dragging, _ in
                        dragging = true
                    }
                    .onChanged { _ in onDragChanged() }
                    .onEnded { _ in onDragEnded() }
            )
            .transition(pillTransition)
        }
    }

    private func pillSurface(_ shape: PillShape) -> some View {
        let isIdle = shape == .idle
        var isEdit = false
        if case .dictation(edit: true, _, _) = shape {
            isEdit = true
        }
        return EvenWidth {
            pillContent(shape)
        }
        // The capsule reveals new content as it grows and hides old content
        // as it shrinks; nothing draws outside the glass.
        .clipShape(Capsule())
        .liquidGlassPill(
            fill: isIdle ? theme.idleFill : theme.fill,
            plate: isIdle ? nil : theme.plate,
            glassTint: isIdle ? theme.idleGlassTint : theme.glassTint,
            stroke: isIdle ? theme.idleStroke : isEdit ? Self.editModeTint.opacity(0.7) : theme.stroke,
            strokeWidth: isIdle ? 0.8 : 1,
            interactive: isInteractive
        )
    }

    @ViewBuilder
    private func pillContent(_ shape: PillShape) -> some View {
        switch shape {
        case .hidden:
            EmptyView()
        case .idle:
            Color.clear
                .frame(width: FloatingIndicatorMetrics.idlePillSize.width, height: FloatingIndicatorMetrics.idlePillSize.height)
        case .hover:
            hoverContent
                .transition(contentTransition)
                .frame(width: FloatingIndicatorMetrics.hoverPillSize.width, height: FloatingIndicatorMetrics.hoverPillSize.height)
        case let .meeting(expanded, _, _, showsTime):
            if let meeting = model.meeting {
                let size = FloatingIndicatorMetrics.meetingPillSize(for: meeting, expanded: expanded, showsTime: showsTime)
                MeetingPillContent(session: meeting, showsTime: showsTime, expanded: expanded, onAction: onMeetingAction)
                    .transition(contentTransition)
                    .frame(width: size.width, height: size.height)
            }
        case let .dictation(edit, message, meetingTime):
            dictationContent(edit: edit, message: message, meetingTime: meetingTime)
        case let .notice(message):
            CappedWidth(maxWidth: FloatingIndicatorMetrics.noticeMaxTextWidth) {
                Text(numbers: message)
                    .font(PillTheme.textFont)
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: FloatingIndicatorMetrics.pillHeight)
            .transition(contentTransition)
        }
    }

    /// Listening and working share this content, so the dots carry on from
    /// the voice into the working light without starting over.
    private func dictationContent(edit: Bool, message: String?, meetingTime: Bool?) -> some View {
        HStack(spacing: 8) {
            if let meeting = model.meeting, let meetingTime {
                MeetingPillTimer(session: meeting, showsTime: meetingTime)
                    .padding(.leading, 14)
                    .transition(contentTransition)
            }
            if edit {
                Image(systemName: "pencil.line")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Self.editModeTint)
                    .padding(.leading, meetingTime == nil ? 14 : 0)
                    .transition(contentTransition)
            }
            DotScopeField(
                stage: fieldStage,
                palette: theme.dots(edit: edit),
                voice: model.voice,
                reduceMotion: reduceMotion
            )
            .frame(
                width: message == nil ? FloatingIndicatorMetrics.dictationPillSize.width : FloatingIndicatorMetrics.compactFieldWidth,
                height: FloatingIndicatorMetrics.pillHeight
            )
            if let message {
                CappedWidth(maxWidth: FloatingIndicatorMetrics.noticeMaxTextWidth) {
                    Text(numbers: message)
                        .font(PillTheme.textFont)
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                }
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .id(message)
                .transition(contentTransition)
            }
        }
        .frame(minHeight: FloatingIndicatorMetrics.pillHeight)
    }

    /// The step lives outside the pill's shape: a switch from transcribing
    /// to formatting changes only the dots, never the pill.
    private var fieldStage: DotScopeStage {
        switch state {
        case .listening:
            return .listening
        case .processing(.formatting, _):
            return .formatting
        case .idle, .hover, .processing, .error:
            return .working
        }
    }

    private var hoverContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.icon)
                .frame(width: 18, height: 18)

            HStack(spacing: 4) {
                ForEach(0 ..< 10, id: \.self) { _ in
                    Circle()
                        .fill(theme.restDot)
                        .frame(width: 3.2, height: 3.2)
                }
            }
        }
    }

    private var isInteractive: Bool {
        state.showsMeetingPill(hasMeeting: model.meeting != nil) || state.acceptsClicks
    }

    static let editModeTint = Color.purple
}

/// Rounds its content's width up to whole even points, so a pill centered in
/// the even-width panel never lands on a half point.
private struct EvenWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        return CGSize(width: (size.width / 2).rounded(.up) * 2, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(bounds.size))
    }
}

/// Blur, fade and a slight shrink: the bridge between two contents of the pill.
private struct SoftFade: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 3 * amount)
            .opacity(1 - amount)
            .scaleEffect(1 - 0.06 * amount)
    }
}

private extension View {
    /// Pill / hint surface. On macOS 26+ a Liquid Glass capsule with a
    /// light tint, and a dark `plate` inside it for active states;
    /// `.interactive()` only on tappable states, per Apple's guidance. No
    /// GlassEffectContainer: inside one, the glass replaces the view's own
    /// transition with its materialize effect, which swells past the pill's
    /// anchored edge. On macOS 14/15 the solid capsule `fill` + stroke.
    @ViewBuilder
    func liquidGlassPill(
        fill: Color,
        plate: Color?,
        glassTint: Color,
        stroke: Color,
        strokeWidth: CGFloat,
        interactive: Bool
    ) -> some View {
        if #available(macOS 26, *) {
            background(Capsule().fill(plate ?? .clear))
                .glassEffect(
                    interactive ? .regular.tint(glassTint).interactive() : .regular.tint(glassTint),
                    in: Capsule()
                )
        } else {
            background(fill)
                .overlay(Capsule().stroke(stroke, lineWidth: strokeWidth))
                .clipShape(Capsule())
        }
    }
}

/// Live-preview transcript text. Shows the newest two lines pinned to the
/// bottom; when the transcript is longer, the older remainder scrolls up out of
/// view and the top edge fades to transparent — no ellipsis. The fade engages
/// only while the text actually overflows two lines, so a short partial renders
/// fully solid with no phantom "cut off" marker.
private struct LivePreviewText: View {
    let text: String
    @Environment(\.pillTheme) private var theme

    /// Natural height of the full (unclamped) transcript at the bubble's width.
    @State private var fullHeight: CGFloat = 0
    /// Height of exactly two rendered lines, measured with the same font so the
    /// overflow test matches real metrics regardless of the resolved typeface.
    @State private var twoLineHeight: CGFloat = 0

    private var isOverflowing: Bool {
        twoLineHeight > 0 && fullHeight > twoLineHeight + 0.5
    }

    var body: some View {
        Text(text)
            .font(AppTypography.subheadline)
            .foregroundStyle(theme.previewText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: FullHeightKey.self, value: proxy.size.height)
                }
            )
            // One or two lines sit centered in the bubble; only once the
            // transcript overflows do we pin the newest line to the bottom and
            // fade the older text out at the top.
            .frame(
                height: twoLineHeight > 0 ? twoLineHeight : nil,
                alignment: isOverflowing ? .bottom : .center
            )
            .clipped()
            .mask(alignment: .bottom) {
                if isOverflowing {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.58)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    Rectangle()
                }
            }
            .background(
                Text("Ag\nAg")
                    .font(AppTypography.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: TwoLineHeightKey.self, value: proxy.size.height)
                        }
                    )
            )
            .onPreferenceChange(FullHeightKey.self) { fullHeight = $0 }
            .onPreferenceChange(TwoLineHeightKey.self) { twoLineHeight = $0 }
            .contentTransition(.interpolate)
            .animation(.easeInOut(duration: 0.18), value: text)
    }
}

private struct FullHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TwoLineHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The pill while a meeting records. At rest: the dot, the time when it
/// shows, and one level meter for the louder track, or a pause glyph while
/// paused, or a warning glyph while a track has a problem. On hover: Pause
/// (or Resume), Stop and Open Notes. A click on the pill opens the meeting.
private struct MeetingPillContent: View {
    let session: MeetingSession
    let showsTime: Bool
    let expanded: Bool
    let onAction: (MeetingPillAction) -> Void
    @Environment(\.pillTheme) private var theme

    var body: some View {
        HStack(spacing: FloatingIndicatorMetrics.meetingPillGap) {
            MeetingPillTimer(session: session, showsTime: showsTime, spacing: FloatingIndicatorMetrics.meetingPillGap)
            if expanded {
                MeetingPillButton(title: session.isPaused ? "Resume" : "Pause", icon: session.isPaused ? "record.circle" : "pause.fill") {
                    onAction(session.isPaused ? .resume : .pause)
                }
                MeetingPillButton(title: "Stop", icon: "stop.fill", iconTint: Color(red: 1, green: 0.353, blue: 0.322)) {
                    onAction(.stop)
                }
                MeetingPillButton(title: "Open Notes") {
                    onAction(.open)
                }
            } else if session.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.mutedIcon)
                    .frame(width: FloatingIndicatorMetrics.meetingPillGlyphWidth)
            } else if session.hasTrackProblem {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.icon, Color(red: 0.95, green: 0.57, blue: 0))
                    .frame(width: FloatingIndicatorMetrics.meetingPillGlyphWidth)
            } else {
                // The bars at rest show that capture works: there is no live
                // transcript to show it.
                MeetingLevelMeter(
                    level: max(session.youLevel, session.themLevel),
                    tint: theme.icon,
                    restTint: theme.mutedIcon.opacity(0.6),
                    barWidth: 2,
                    height: 16
                )
            }
        }
        .foregroundStyle(theme.text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.isPaused ? "Meeting paused" : "Meeting recording")
        .accessibilityAction(named: session.isPaused ? "Resume" : "Pause") {
            onAction(session.isPaused ? .resume : .pause)
        }
        .accessibilityAction(named: "Stop") { onAction(.stop) }
        .accessibilityAction(named: "Open Notes") { onAction(.open) }
    }
}

/// A button of the hovered pill: text on a faint wash.
private struct MeetingPillButton: View {
    let title: String
    var icon: String?
    var iconTint: Color?
    let action: () -> Void
    @Environment(\.pillTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(iconTint ?? theme.icon)
                        .frame(width: FloatingIndicatorMetrics.meetingPillIconWidth)
                }
                Text(title)
                    .font(Font(FloatingIndicatorMetrics.meetingPillButtonFont))
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(theme.buttonWash))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.95))
    }
}

/// The meeting's dot and recorded time. The dot is gray and the time dimmed
/// while paused.
private struct MeetingPillTimer: View {
    let session: MeetingSession
    let showsTime: Bool
    var spacing: CGFloat = 7
    @Environment(\.pillTheme) private var theme

    var body: some View {
        HStack(spacing: spacing) {
            Circle()
                .fill(session.isPaused ? Color.gray : Color.red)
                .frame(width: FloatingIndicatorMetrics.meetingPillDotWidth, height: FloatingIndicatorMetrics.meetingPillDotWidth)
            if showsTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(MeetingTranscript.clock(session.elapsed(at: context.date)))
                        .font(Font(FloatingIndicatorMetrics.meetingPillTimeFont))
                        .foregroundStyle(session.isPaused ? theme.mutedIcon : theme.text)
                }
            }
        }
    }
}
