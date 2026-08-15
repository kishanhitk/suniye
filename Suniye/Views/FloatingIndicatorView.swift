import AppKit
import Observation
import SwiftUI

/// Observable state feeding the floating indicator. The controller mutates
/// `state` in place rather than rebuilding the hosting view's root, so SwiftUI's
/// own implicit animations actually run — reassigning the whole rootView each
/// tick discards in-flight animations and makes every transition snap.
@MainActor
@Observable
final class FloatingIndicatorModel {
    var state: FloatingIndicatorState = .idle
}

struct FloatingIndicatorView: View {
    let model: FloatingIndicatorModel
    let onHoverChanged: (Bool) -> Void
    let onAction: () -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    private var state: FloatingIndicatorState { model.state }

    var body: some View {
        glassGrouped {
            VStack(spacing: topAccessorySpacing) {
                if let helperText {
                    Text(helperText)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        // Static hint text — no `.interactive()` (the tap lives
                        // on the pill below, not here).
                        .liquidGlassPill(
                            fill: capsuleFill,
                            glassTint: capsuleGlassTint,
                            stroke: capsuleStroke,
                            strokeWidth: capsuleBorderWidth,
                            interactive: false
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
                }

                if let previewText {
                    previewBubble(previewText)
                }

                capsule
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, helperText == nil ? 0 : 4)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        // Non-overshooting so the growing pill/bubble never pokes past the
        // (instantly-sized) window bounds mid-animation.
        .animation(.smooth(duration: 0.3), value: state.layoutAnimationKey)
        // Animate the live-preview bubble's appearance/disappearance. Keyed on
        // presence only (not the text), so it fires once when the bubble shows
        // or hides — per-tick text changes crossfade inside LivePreviewText.
        .animation(.smooth(duration: 0.28), value: previewText != nil)
        // The indicator is dark chrome in both appearances: force the dark
        // color scheme so the pill's Liquid Glass renders its dark material in
        // Light Mode too, keeping its white content legible.
        .environment(\.colorScheme, .dark)
    }

    /// Groups the indicator's glass surfaces in a GlassEffectContainer on
    /// macOS 26+ so the hover-hint capsule and the pill share one sampling
    /// region (per Apple's guidance). No-op on the blur fallback.
    @ViewBuilder
    private func glassGrouped<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: FloatingIndicatorMetrics.previewBubbleGap) {
                content()
            }
        } else {
            content()
        }
    }

    private static let previewBubbleShape = RoundedRectangle(
        cornerRadius: FloatingIndicatorMetrics.previewBubbleSize.height / 2,
        style: .continuous
    )

    /// Detached live-preview bubble above the pill. Fixed geometry (see
    /// FloatingIndicatorMetrics) so only the text content changes per tick, and
    /// non-interactive so the pill keeps all click/drag behavior.
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
                        material: .hudWindow,
                        state: .active,
                        cornerRadius: FloatingIndicatorMetrics.previewBubbleSize.height / 2
                    )
                    Color.black.opacity(0.35)
                }
            }
            .overlay(Self.previewBubbleShape.stroke(capsuleStroke, lineWidth: capsuleBorderWidth))
            .clipShape(Self.previewBubbleShape)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .allowsHitTesting(false)
            .transition(.asymmetric(
                insertion: .opacity
                    .combined(with: .scale(scale: 0.96, anchor: .bottom))
                    .combined(with: .offset(y: 6))
                    .animation(.easeOut(duration: 0.25)),
                removal: .opacity.animation(.easeOut(duration: 0.15))
            ))
    }

    private var previewText: String? {
        if case let .listening(_, _, preview) = state {
            return preview.text
        }
        return nil
    }

    private var topAccessorySpacing: CGFloat {
        if helperText != nil {
            return 8
        }
        return previewText == nil ? 0 : FloatingIndicatorMetrics.previewBubbleGap
    }

    private var capsule: some View {
        HStack(spacing: 10) {
            capsuleContent
        }
        .padding(.horizontal, horizontalPadding)
        .frame(width: pillWidth, height: pillHeight)
        .liquidGlassPill(
            fill: capsuleFill,
            glassTint: capsuleGlassTint,
            stroke: capsuleStroke,
            strokeWidth: capsuleBorderWidth,
            interactive: isInteractive
        )
        .contentShape(Capsule())
        .onTapGesture {
            guard isInteractive else { return }
            onAction()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    guard isDraggable else { return }
                    onDragChanged()
                }
                .onEnded { _ in
                    guard isDraggable else { return }
                    onDragEnded()
                }
        )
    }

    @ViewBuilder
    private var capsuleContent: some View {
        switch state {
        case .idle:
            EmptyView()
        case .hover:
            hoverContent
        case let .listening(levels, source, _):
            if source == .editHotkey {
                Image(systemName: "pencil.line")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FloatingIndicatorView.editModeTint)
            }
            ListeningMeterView(levels: levels)
        case let .processing(message):
            processingContent(message: message)
        case let .error(message):
            Text(message)
                .font(AppTypography.subheadlineSemibold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private var hoverContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)

            dotTrack(count: 10)
        }
    }

    private func processingContent(message: String?) -> some View {
        HStack(spacing: 10) {
            if let message {
                Text(message)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                dotTrack(count: 8)
            }
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.92))
        }
    }

    private var helperText: String? {
        if case .hover = state {
            return "Click or hold fn to start dictating"
        }
        return nil
    }

    private var isInteractive: Bool {
        switch state {
        case .hover:
            return true
        case let .listening(_, source, _):
            return source == .manual
        default:
            return false
        }
    }

    private var isDraggable: Bool {
        switch state {
        case .idle, .hover:
            return true
        case .listening, .processing, .error:
            return false
        }
    }

    private var capsuleFill: Color {
        switch state {
        case .idle:
            return Color.black.opacity(0.58)
        default:
            return Color.black.opacity(0.96)
        }
    }

    /// Tint for the Liquid Glass pill — much lighter than `capsuleFill` so the
    /// glass material shows through instead of being smothered. Legibility of
    /// the white content leans on the forced dark color scheme.
    private var capsuleGlassTint: Color {
        switch state {
        case .idle:
            return Color.black.opacity(0.35)
        default:
            return Color.black.opacity(0.55)
        }
    }

    private var capsuleStroke: Color {
        switch state {
        case .idle:
            return Color.white.opacity(0.34)
        case .listening(_, .editHotkey, _):
            return FloatingIndicatorView.editModeTint.opacity(0.7)
        default:
            return Color.white.opacity(0.14)
        }
    }

    static let editModeTint = Color.purple

    private var capsuleBorderWidth: CGFloat {
        switch state {
        case .idle:
            return 0.8
        default:
            return 1
        }
    }

    private var pillWidth: CGFloat {
        switch state {
        case .idle:
            return 74
        case .hover:
            return 152
        case let .listening(_, source, _):
            return FloatingIndicatorMetrics.pillSize(source: source).width
        case let .processing(message):
            guard let message else {
                return 128
            }
            return min(max(CGFloat(message.count) * 6.5 + 54, 260), 360)
        case let .error(message):
            return min(max(CGFloat(message.count) * 6.4, 170), 240) + 16
        }
    }

    private var pillHeight: CGFloat {
        switch state {
        case .idle:
            return 7
        case .hover:
            return 32
        case .listening:
            return FloatingIndicatorMetrics.listeningPillSize.height
        case .processing:
            return 40
        case .error:
            return 52
        }
    }

    private var horizontalPadding: CGFloat {
        switch state {
        case .idle:
            return 0
        case .hover:
            return 14
        case .listening:
            return 14
        case .processing:
            return 14
        case .error:
            return 16
        }
    }

    private func dotTrack(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0 ..< count, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 3.2, height: 3.2)
            }
        }
    }
}

private extension View {
    /// Pill / hover-hint surface. On macOS 26+ a Liquid Glass capsule with a
    /// light tint so the material actually reads as glass (a near-opaque tint
    /// would smother it); `.interactive()` only on tappable states, per Apple's
    /// guidance. On macOS 14/15 the solid capsule `fill` + stroke — identical to
    /// the pre-glass rendering.
    @ViewBuilder
    func liquidGlassPill(
        fill: Color,
        glassTint: Color,
        stroke: Color,
        strokeWidth: CGFloat,
        interactive: Bool
    ) -> some View {
        if #available(macOS 26, *) {
            glassEffect(
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
            .foregroundStyle(.white.opacity(0.95))
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

private struct ListeningMeterView: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 2, height: barHeight(for: index, level: level))
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func barHeight(for index: Int, level: Float) -> CGFloat {
        let normalized = max(0, min(CGFloat(level), 1))
        let centerDistance = abs(CGFloat(index) - CGFloat(max(levels.count - 1, 0)) / 2)
        let envelope = max(0.35, 1 - centerDistance / max(CGFloat(levels.count) / 2, 1))
        return 4 + (normalized * 25 * envelope) + (normalized * 8)
    }
}
