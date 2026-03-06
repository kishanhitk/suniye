import SwiftUI

struct FloatingIndicatorView: View {
    let state: FloatingIndicatorState

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            indicator

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.ui(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .font(AppTypography.ui(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
        .onAppear { updatePulse() }
        .onChange(of: state.logValue) { _, _ in updatePulse() }
    }

    @ViewBuilder
    private var indicator: some View {
        ZStack {
            Circle()
                .fill(indicatorColor.opacity(0.18))
                .frame(width: 38, height: 38)

            if case .processing = state {
                ProgressView()
                    .controlSize(.small)
                    .tint(indicatorColor)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(indicatorColor)
            }

            if case .listening = state {
                Circle()
                    .stroke(indicatorColor.opacity(0.7), lineWidth: 2)
                    .frame(width: 38, height: 38)
                    .scaleEffect(pulse ? 1.28 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.95).repeatForever(autoreverses: false), value: pulse)
            }
        }
    }

    private var title: String {
        switch state {
        case .listening: return "Listening"
        case .stopped: return "Captured"
        case .processing: return "Processing"
        case .done: return "Done"
        case .error: return "Error"
        }
    }

    private var subtitle: String {
        switch state {
        case .listening:
            return "Release hotkey to stop"
        case .stopped:
            return "Audio clip captured"
        case .processing:
            return "Transcribing"
        case let .done(words):
            return words > 0 ? "\(words) words inserted" : "No speech detected"
        case let .error(message):
            return message
        }
    }

    private var symbol: String {
        switch state {
        case .listening: return "mic.fill"
        case .stopped: return "stop.fill"
        case .processing: return "waveform"
        case .done: return "checkmark"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var indicatorColor: Color {
        switch state {
        case .listening: return Color(red: 0.58, green: 0.18, blue: 0.19)
        case .stopped: return Color(red: 0.34, green: 0.34, blue: 0.34)
        case .processing: return Color(red: 0.24, green: 0.31, blue: 0.45)
        case .done: return Color(red: 0.24, green: 0.39, blue: 0.30)
        case .error: return Color(red: 0.56, green: 0.19, blue: 0.20)
        }
    }

    private func updatePulse() {
        pulse = false
        if case .listening = state {
            pulse = true
        }
    }
}
