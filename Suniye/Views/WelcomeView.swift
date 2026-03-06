import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Suniye")
                .font(.system(size: 34, weight: .bold, design: .default))

            Text("Local, low-latency dictation for macOS using Parakeet TDT with sherpa-onnx.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("No cloud transcription in MVP", systemImage: "lock.shield")
                Label("Hold fn/globe to dictate", systemImage: "keyboard")
                Label("Clipboard is preserved after paste", systemImage: "doc.on.clipboard")
            }
            .font(.system(size: 14))

            Spacer()

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }
}
