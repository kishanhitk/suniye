import SwiftUI

struct FloatingIndicatorView: View {
    let state: FloatingIndicatorState
    let onHoverChanged: (Bool) -> Void
    let onAction: () -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        VStack(spacing: helperText == nil ? 0 : 8) {
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

            capsule
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, helperText == nil ? 0 : 4)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: state)
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
        case let .listening(levels, source, preview):
            if source == .editHotkey {
                Image(systemName: "pencil.line")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FloatingIndicatorView.editModeTint)
            }
            ListeningMeterView(levels: levels)
            if let preview {
                Text(preview)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
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
        case let .listening(_, source, preview):
            guard let preview else {
                return source == .editHotkey ? 150 : 124
            }
            return min(max(CGFloat(preview.count) * 6.5 + 96, 220), 460)
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
        case .listening, .processing:
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
