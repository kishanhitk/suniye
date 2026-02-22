import SwiftUI

struct FloatingIndicatorView: View {
    let state: FloatingIndicatorState

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            indicator

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 12)
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
                .frame(width: 42, height: 42)

            if case .processing = state {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }

            if case .listening = state {
                Circle()
                    .stroke(indicatorColor.opacity(0.9), lineWidth: 2)
                    .frame(width: 42, height: 42)
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
