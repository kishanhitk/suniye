import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Voice to text,\nanywhere on your Mac")
                .font(.custom("Google Sans", fixedSize: 22).weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                benefitRow(
                    icon: "lock.shield",
                    title: "Private by design",
                    detail: "Your voice stays on your Mac."
                )
                benefitRow(
                    icon: "bolt.fill",
                    title: "No cloud delay",
                    detail: "Super-low latency. Near-instant dictation."
                )
                benefitRow(
                    icon: "wifi.slash",
                    title: "Works offline",
                    detail: "Keep dictating without an internet connection."
                )
            }
        }
    }

    private func benefitRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MainWindowPalette.secondaryText)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(Color.primary)
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
