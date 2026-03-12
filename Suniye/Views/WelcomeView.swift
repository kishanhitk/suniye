import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Suniye")
                .font(AppTypography.pageTitle)

            Text("Local, low-latency dictation for macOS using Parakeet TDT with sherpa-onnx.")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label("No cloud transcription in MVP", systemImage: "lock.shield")
                Label("Hold fn/globe to dictate", systemImage: "keyboard")
                Label("Clipboard is preserved after paste", systemImage: "doc.on.clipboard")
            }
            .font(AppTypography.subheadline)

            Spacer()

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }
}
