import AppKit
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            Text("Suniye")
                .font(AppTypography.bodyMedium)
                .foregroundStyle(MainWindowPalette.secondaryText)

            Text("Voice to text,\nanywhere on your Mac")
                .font(.custom("Google Sans", fixedSize: 22).weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                benefitRow(icon: "lock.shield", text: "Private — audio never leaves your device")
                benefitRow(icon: "bolt.fill", text: "Offline — no internet required")
                benefitRow(icon: "macwindow.on.rectangle", text: "Works in every app")
            }
            .padding(.top, 4)
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
    }
}
