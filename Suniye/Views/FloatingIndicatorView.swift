import SwiftUI

struct FloatingIndicatorView: View {
    let state: FloatingIndicatorState

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            indicator

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
        .onAppear {
            updatePulse()
        }
        .onChange(of: state.logValue) { _, _ in
            updatePulse()
        }
    }

    @ViewBuilder
    private var indicator: some View {
        ZStack {
            Circle()
                .fill(indicatorColor.opacity(0.22))
                .frame(width: 34, height: 34)

            if case .processing = state {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }

            if case .listening = state {
                Circle()
                    .stroke(indicatorColor.opacity(0.9), lineWidth: 1.5)
                    .frame(width: 34, height: 34)
                    .scaleEffect(pulse ? 1.35 : 0.95)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.95).repeatForever(autoreverses: false), value: pulse)
            }
        }
    }

    private var title: String {
        switch state {
        case .listening:
            return "Listening"
        case .stopped:
            return "Stopped"
        case .processing:
            return "Processing"
        case .done:
            return "Done"
        case .error:
            return "Error"
        }
    }

    private var subtitle: String {
        switch state {
        case .listening:
            return "Release Fn to stop recording"
        case .stopped:
            return "Captured audio clip"
        case .processing:
            return "Transcribing..."
        case let .done(words):
            return words > 0 ? "\(words) words inserted" : "No speech detected"
        case let .error(message):
            return message
        }
    }

    private var symbol: String {
        switch state {
        case .listening:
            return "mic.fill"
        case .stopped:
            return "stop.fill"
        case .processing:
            return "waveform"
        case .done:
            return "checkmark"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var indicatorColor: Color {
        switch state {
        case .listening:
            return .red
        case .stopped:
            return .orange
        case .processing:
            return .blue
        case .done:
            return .green
        case .error:
            return .yellow
        }
    }

    private func updatePulse() {
        pulse = false
        if case .listening = state {
            pulse = true
        }
    }
}
