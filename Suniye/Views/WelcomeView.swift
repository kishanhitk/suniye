import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Voice to text,\nanywhere on your Mac")
                .font(.custom("Google Sans", fixedSize: 22).weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 14) {
                benefitRow(icon: "lock.shield", text: "Private — runs on your device")
                benefitRow(icon: "bolt.fill", text: "Offline — no internet required")
                benefitRow(icon: "macwindow.on.rectangle", text: "Works in every app")
            }
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MainWindowPalette.secondaryText)
                .frame(width: 20)
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
        .fixedSize()
    }
}
