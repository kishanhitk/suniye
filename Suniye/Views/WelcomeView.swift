import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Write at the speed of thought.")
                .font(AppTypography.onboardingTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                benefitRow(
                    icon: "lock.shield",
                    title: "Private by design"
                )
                benefitRow(
                    icon: "bolt.fill",
                    title: "No cloud delay"
                )
                benefitRow(
                    icon: "wifi.slash",
                    title: "Works offline"
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
        }
    }

    private func benefitRow(icon: String, title: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MainWindowPalette.secondaryText)

            Text(title)
                .font(AppTypography.subheadlineSemibold)
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
