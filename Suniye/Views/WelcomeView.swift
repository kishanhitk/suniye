import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Suniye")
                .font(AppTypography.ui(size: 48, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)

            Text("Local-first dictation for macOS. Hold your hotkey, speak, and paste into any active app.")
                .font(AppTypography.ui(size: 21, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)

            AppShellCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Audio and transcription stay local", systemImage: "lock.shield")
                    Label("Hold-to-talk hotkey workflow", systemImage: "keyboard")
                    Label("Clipboard preservation after paste", systemImage: "doc.on.clipboard")
                }
                .font(AppTypography.ui(size: 17, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
                .padding(16)
            }

            Spacer()

            Button("Get started") {
                onContinue()
            }
            .buttonStyle(PrimaryDarkButtonStyle())
        }
        .padding(28)
        .background(AppTheme.panelBackground)
    }
}
