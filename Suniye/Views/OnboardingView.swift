import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    @State private var step: Step = .welcome

    enum Step {
        case welcome
        case download
    }

    var body: some View {
        ZStack {
            AppTheme.windowBackground
                .ignoresSafeArea()

            AppShellCard {
                if step == .welcome {
                    WelcomeView {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step = .download
                        }
                    }
                } else {
                    ModelDownloadView(appState: appState)
                }
            }
            .frame(maxWidth: 840, maxHeight: 520)
            .padding(24)
        }
    }
}
