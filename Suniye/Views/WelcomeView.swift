import AppKit
import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)

                Text("Suniye")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            Text("Local-first dictation for macOS.")
                .font(AppTypography.pageTitle)

            Text("Hold the shortcut, speak, and release to paste spoken text into the app you're using.")
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Label("Audio stays on your Mac", systemImage: "lock.shield")
                Label("Uses an offline speech model", systemImage: "cpu")
                Label("Works in any app after setup", systemImage: "rectangle.on.rectangle")
            }
            .font(AppTypography.subheadline)
            .foregroundStyle(MainWindowPalette.secondaryText)

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
