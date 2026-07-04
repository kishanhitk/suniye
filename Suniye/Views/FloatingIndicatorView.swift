import AppKit
import SwiftUI

struct FloatingIndicatorView: View {
    let state: FloatingIndicatorState
    let onHoverChanged: (Bool) -> Void
    let onAction: () -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        VStack(spacing: topAccessorySpacing) {
            if let helperText {
                Text(helperText)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(capsuleFill)
                    .overlay(
                        Capsule()
                            .stroke(capsuleStroke, lineWidth: capsuleBorderWidth)
                    )
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            }

            if let previewText {
                previewBubble(previewText)
            }

            capsule
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, helperText == nil ? 0 : 4)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: state.layoutAnimationKey)
    }

    private static let previewBubbleShape = RoundedRectangle(
        cornerRadius: FloatingIndicatorMetrics.previewBubbleSize.height / 2,
        style: .continuous
    )

    /// Detached live-preview bubble above the pill. Fixed geometry (see
    /// FloatingIndicatorMetrics) so only the text content changes per tick, and
    /// non-interactive so the pill keeps all click/drag behavior.
    private func previewBubble(_ text: String) -> some View {
        let segments = FloatingIndicatorMetrics.previewSegments(text)
        return (
            Text(segments.head).foregroundStyle(.white.opacity(0.55))
                + Text(segments.tail).foregroundStyle(.white.opacity(0.95))
        )
        .font(AppTypography.subheadline)
        .lineLimit(2)
        .truncationMode(.head)
        .multilineTextAlignment(.leading)
        .contentTransition(.interpolate)
        .animation(.easeInOut(duration: 0.18), value: text)
        .padding(.horizontal, 20)
        .frame(
            width: FloatingIndicatorMetrics.previewBubbleSize.width,
            height: FloatingIndicatorMetrics.previewBubbleSize.height,
            alignment: .leading
        )
        .background {
            ZStack {
                BehindWindowBlur(cornerRadius: FloatingIndicatorMetrics.previewBubbleSize.height / 2)
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
        .background(capsuleFill)
        .overlay(
            Capsule()
                .stroke(capsuleStroke, lineWidth: capsuleBorderWidth)
        )
        .clipShape(Capsule())
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

/// Behind-window blur for the preview bubble. SwiftUI materials only blur
/// content within the same window, and this panel is transparent — real blur
/// of whatever is behind the panel needs NSVisualEffectView with
/// `.behindWindow` blending. The blur region is masked via `maskImage`
/// (a plain CALayer mask does not constrain behind-window blur).
private struct BehindWindowBlur: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = .roundedRectMask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private extension NSImage {
    static func roundedRectMask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
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
