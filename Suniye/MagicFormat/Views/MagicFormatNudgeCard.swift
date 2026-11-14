import SwiftUI

/// Post-onboarding Magic Format pitch, shown once the user has real dictations
/// to judge it against. The before/after snippet makes the value concrete.
struct MagicFormatNudgeCard: View {
    let onSetUp: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(Color.accentColor)
                    Text("Make dictations cleaner")
                        .font(AppTypography.bodyMedium)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{201C}so um send the report friday\u{201D}")
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.tertiaryText)
                        .strikethrough(color: MainWindowPalette.tertiaryText)
                    Text("\u{201C}Send the report by Friday.\u{201D}")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.primary)
                }

                Text("Magic Format fixes punctuation and filler words on your Mac, before text is pasted.")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Set Up Magic Format", action: onSetUp)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Not Now", action: onDismiss)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
