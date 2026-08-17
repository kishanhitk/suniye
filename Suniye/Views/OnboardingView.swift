import AppKit
import SwiftUI

/// The 3-screen onboarding flow. Screen order is the product thesis:
/// 1. Welcome       — value + starts the model download in the background
/// 2. Prepare/Try   — prerequisites first, then the first successful dictation
/// 3. Type Anywhere — the Accessibility ask, made after value is demonstrated
struct OnboardingView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let appIdentity = AppIdentity.current

    private var step: OnboardingStep {
        appState.activeOnboardingStep ?? .welcome
    }

    var body: some View {
        VStack(spacing: 0) {
            onboardingProgressDots
                .padding(.top, 28)

            Spacer()

            onboardingBrandHeader

            stepContent
                .frame(maxWidth: 420)
                .padding(.top, 20)
                .id(step)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                )

            Spacer(minLength: 24)

            navigationButtons
                .frame(maxWidth: 420)
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MainWindowPalette.windowBackground)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
        .onAppear {
            appState.refreshPermissionStatus()
        }
        .onChange(of: appState.activeOnboardingStep) { _, _ in
            appState.refreshPermissionStatus()
        }
    }

    // MARK: - Progress

    private var onboardingProgressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : MainWindowPalette.cardStroke)
                    .frame(width: 6, height: 6)

                if s != OnboardingStep.allCases.last {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(s.rawValue < step.rawValue ? Color.accentColor.opacity(0.5) : MainWindowPalette.cardStroke)
                        .frame(width: 24, height: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count): \(step.title)")
    }

    private var onboardingBrandHeader: some View {
        let iconSize = AppMetrics.onboardingBrandIconSize

        return VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)

            Text(appIdentity.displayName)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        VStack(spacing: 18) {
            switch step {
            case .welcome:
                welcomeContent
            case .speak:
                speakContent
            case .typeAnywhere:
                typeAnywhereContent
            }
        }
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(spacing: 16) {
            WelcomeView()

            if let message = appState.onboardingDiskSpaceMessage {
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var analyticsDisclosure: some View {
        HStack(spacing: 4) {
            Text(appState.shareAnalyticsEnabled
                 ? "Anonymous usage stats help improve \(appIdentity.displayName)."
                 : "Anonymous usage stats are off.")
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)

            if appState.shareAnalyticsEnabled {
                Button("Turn off") {
                    appState.shareAnalyticsEnabled = false
                }
                .buttonStyle(.plain)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .underline()
                .accessibilityLabel("Turn off anonymous usage stats")
            }
        }
    }

    // MARK: - Prepare / Try (the aha screen)

    private var speakContent: some View {
        VStack(alignment: .center, spacing: 14) {
            VStack(alignment: .center, spacing: 6) {
                Text(canPracticeOnboarding ? "Try your first dictation" : "Prepare Suniye")
                    .font(AppTypography.onboardingTitle)
                    .multilineTextAlignment(.center)
                Text(speakSubtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !appState.hasMicPermission {
                microphoneCard
            }

            if !appState.asrModelReady {
                modelStatusLine
            }

            if canPracticeOnboarding {
                practicePrompt
                transcriptPreview
            }

            if appState.isOnboardingPracticeRecording {
                practiceStatusLabel("Listening...", color: .accentColor)
            } else if appState.isOnboardingPracticeProcessing {
                practiceStatusLabel("Transcribing...", color: .accentColor)
            } else if let result = appState.onboardingPracticeResult {
                practiceStatusLabel(result.message, color: result.severity.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var speakSubtitle: String {
        if !appState.hasMicPermission && !appState.asrModelReady {
            return "Allow microphone access while the speech model prepares on your Mac."
        }
        if !appState.hasMicPermission {
            return "Allow microphone access to try your first dictation."
        }
        if !appState.asrModelReady {
            return "The speech model is preparing on your Mac."
        }
        return "Hold \(appState.hotkeyConfiguration.displayString) and say:"
    }

    private var canPracticeOnboarding: Bool {
        appState.hasMicPermission && appState.asrModelReady
    }

    private var microphoneCard: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(MainWindowPalette.secondaryText)
                    Text("Microphone")
                        .font(AppTypography.bodyMedium)
                    Spacer(minLength: 12)

                    if appState.hasMicPermissionBeenDenied {
                        Button("Open Settings") {
                            appState.openMicrophonePrivacySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Open System Settings to enable the microphone")
                    } else {
                        Button("Allow Microphone") {
                            appState.requestMicrophonePermission(askSurface: .onboarding)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Allow microphone access")
                    }
                }

                Text(appState.hasMicPermissionBeenDenied
                     ? "Microphone access was denied. Turn it on in System Settings, then come back — this screen updates by itself."
                     : "\(appIdentity.displayName) listens only while you hold the hotkey. Audio never leaves your Mac.")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var modelStatusLine: some View {
        HStack(spacing: 8) {
            if appState.phase == .downloadingModel {
                ProgressView(value: appState.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 76)

                Text("Downloading speech model")

                Spacer(minLength: 4)

                Text(verbatim: "\(Int(appState.downloadProgress * 100))%")
                    .font(AppTypography.codeCaption)

                Button("Cancel") {
                    appState.cancelASRModelDownload()
                }
                .buttonStyle(.plain)
                .underline()
                .disabled(!appState.canCancelASRModelDownload)
                .accessibilityLabel("Cancel the model download")
            } else if appState.phase == .loading {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading speech model")
            } else if appState.phase == .error {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)

                Text("Speech model is not ready")

                Spacer(minLength: 4)

                Button("Retry") {
                    appState.startModelDownload()
                }
                .buttonStyle(.plain)
                .underline()
            } else {
                Text("Speech model is not ready")

                Spacer(minLength: 4)

                Button("Download") {
                    appState.startModelDownload()
                }
                .buttonStyle(.plain)
                .underline()
            }
        }
        .font(AppTypography.caption)
        .foregroundStyle(MainWindowPalette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var transcriptPlaceholder: String {
        "Your words will appear here after you speak."
    }

    private var practicePrompt: some View {
        Text("\u{201C}Send the report by Friday morning.\u{201D}")
            .font(AppTypography.body)
            .foregroundStyle(MainWindowPalette.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var transcriptPreview: some View {
        let isActive = appState.isOnboardingPracticeRecording

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcript preview")
                    .font(AppTypography.bodyMedium)
            }

            ScrollView {
                Text(appState.onboardingPracticeText.isEmpty
                     ? transcriptPlaceholder
                     : appState.onboardingPracticeText)
                    .font(AppTypography.body)
                    .foregroundStyle(appState.onboardingPracticeText.isEmpty
                        ? MainWindowPalette.tertiaryText
                        : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 82)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MainWindowPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? Color.accentColor : MainWindowPalette.cardStroke,
                        lineWidth: isActive ? 1.5 : 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Read-only transcript preview")
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private func practiceStatusLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Type Anywhere (Accessibility, post-aha)

    private var typeAnywhereContent: some View {
        VStack(alignment: .center, spacing: 14) {
            VStack(alignment: .center, spacing: 6) {
                Text("Dictate anywhere")
                    .font(AppTypography.onboardingTitle)
                    .multilineTextAlignment(.center)
                Text(appState.hasAccessibilityPermission
                     ? "Hold \(appState.hotkeyConfiguration.displayString) in any app to dictate."
                     : "Allow \(appIdentity.displayName) to type into the app you are using.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SurfaceCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.raised")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        Text(appState.hasAccessibilityPermission ? "Ready to dictate" : "Type into any app")
                            .font(AppTypography.bodyMedium)
                        Spacer(minLength: 12)

                        if appState.hasAccessibilityPermission {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 15))
                                .accessibilityLabel("Accessibility granted")
                        } else {
                            HStack(spacing: 8) {
                                Button("Open Settings") {
                                    appState.openAccessibilityPrivacySettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Open System Settings to enable Accessibility")

                                Button("Allow Access") {
                                    appState.beginAccessibilityOnboarding(askSurface: .onboarding)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityLabel("Enable Accessibility")
                            }
                        }
                    }

                    if appState.hasAccessibilityPermission {
                        HStack(spacing: 10) {
                            Text("Try it in Notes. Click into a note and hold \(appState.hotkeyConfiguration.displayString).")
                                .font(AppTypography.caption)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)

                            Button("Try in Notes") {
                                appState.openNotesForInsertionDemo()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else if appState.accessibilityGrantLikelyStale {
                        Text("macOS reset this permission after an update. In the Accessibility list, toggle \(appIdentity.displayName) off and back on.")
                            .font(AppTypography.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if appState.accessibilityAssistTimedOut {
                        Text("Still waiting for the grant — use Open Settings if the helper got lost.")
                            .font(AppTypography.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Drag \(appIdentity.displayName) into the Accessibility list — takes five seconds. Nothing is ever read from your screen.")
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Navigation

    @ViewBuilder
    private var navigationButtons: some View {
        switch step {
        case .welcome:
            VStack(spacing: 10) {
                Button {
                    Task { await appState.beginOnboardingSetup() }
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                analyticsDisclosure
            }

        case .speak:
            if canPracticeOnboarding || showsSpeakEscapeHatch {
                VStack(spacing: 8) {
                    Button {
                        appState.advanceOnboardingFromSpeak()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.onboardingPracticeSucceeded || isDictationInFlight)
                    .keyboardShortcut(.defaultAction)

                    if !appState.onboardingPracticeSucceeded, showsSpeakEscapeHatch {
                        Button("Skip for now") {
                            appState.advanceOnboardingFromSpeak()
                        }
                        .buttonStyle(.plain)
                        .font(AppTypography.caption)
                        .disabled(isDictationInFlight)
                        .accessibilityHint("Continue without a practice dictation")
                    }
                }
                .frame(maxWidth: .infinity)
            }

        case .typeAnywhere:
            VStack(spacing: 8) {
                Button {
                    appState.finishOnboarding()
                } label: {
                    Text("Finish")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.hasAccessibilityPermission)
                .keyboardShortcut(.defaultAction)

                if !appState.hasAccessibilityPermission {
                    Button("Later — I'll paste with ⌘V") {
                        appState.finishOnboarding()
                    }
                    .buttonStyle(.plain)
                    .font(AppTypography.caption)
                    .accessibilityHint("Finish setup and copy dictations to the clipboard until access is allowed")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var isDictationInFlight: Bool {
        appState.phase == .recording || appState.phase == .transcribing
    }

    /// The Speak screen must never trap anyone: the escape hatch appears after a
    /// failed attempt, a persistent model error, or when the mic was denied.
    private var showsSpeakEscapeHatch: Bool {
        appState.onboardingPracticeAttempts >= 1
            || appState.phase == .error
            || appState.hasMicPermissionBeenDenied
    }

}

private extension OnboardingPracticeResult.Severity {
    var color: Color {
        switch self {
        case .success:
            .green
        case .error:
            .red
        }
    }
}
