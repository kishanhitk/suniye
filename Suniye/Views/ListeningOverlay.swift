import SwiftUI

struct ListeningOverlay: View {
    let isVisible: Bool

    @State private var animate = false

    var body: some View {
        ZStack {
            if isVisible {
                Circle()
                    .stroke(Color.black.opacity(0.18), lineWidth: 4)
                    .frame(width: animate ? 160 : 90, height: animate ? 160 : 90)

                Circle()
                    .stroke(Color.black.opacity(0.12), lineWidth: 2)
                    .frame(width: animate ? 210 : 105, height: animate ? 210 : 105)

                Circle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 74, height: 74)

                Image(systemName: "mic.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [Color(red: 0.96, green: 0.96, blue: 0.92).opacity(isVisible ? 0.52 : 0), .clear],
                center: .center,
                startRadius: 6,
                endRadius: 200
            )
        )
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                withAnimation(.easeOut(duration: 0.75).repeatForever(autoreverses: false)) {
                    animate = true
                }
            } else {
                animate = false
            }
        }
    }
}
