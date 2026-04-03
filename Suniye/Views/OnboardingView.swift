import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState

    private var step: OnboardingStep {
        appState.activeOnboardingStep ?? .welcome
    }

    var body: some View {
        VStack(spacing: 0) {
            onboardingProgressDots
                .padding(.top, 28)

            Spacer()

            stepContent
                .frame(maxWidth: 380)
                .id(step)
                .transition(.opacity)

            Spacer()

            navigationButtons
                .frame(maxWidth: 380)
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MainWindowPalette.windowBackground)
        .animation(.easeInOut(duration: 0.25), value: step)
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

                if s != .practice {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(s.rawValue < step.rawValue ? Color.accentColor.opacity(0.5) : MainWindowPalette.cardStroke)
                        .frame(width: 24, height: 1)
                }
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        VStack(spacing: step == .welcome ? 20 : 18) {
            onboardingBrandHeader

            switch step {
            case .welcome:
                WelcomeView()
            case .setup:
                setupContent
            case .practice:
                practiceContent
            }
        }
    }

    private var onboardingBrandHeader: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            Text("Suniye")
                .font(AppTypography.bodyMedium)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
    }

    // MARK: - Setup

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up Suniye")
                    .font(AppTypography.pageTitle)
                Text("One-time setup. Takes about a minute.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    setupPermissionRow(
                        icon: "hand.raised",
                        title: "Accessibility",
                        isGranted: appState.hasAccessibilityPermission,
                        action: { appState.requestAccessibilityPermission() }
                    )

                    CardDivider()
                        .padding(.horizontal, 14)

                    setupPermissionRow(
                        icon: "mic",
                        title: "Microphone",
                        isGranted: appState.hasMicPermission,
                        action: { appState.requestMicrophonePermission() }
                    )

                    CardDivider()
                        .padding(.horizontal, 14)

                    modelSetupRow
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setupPermissionRow(
        icon: String,
        title: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MainWindowPalette.secondaryText)
                .frame(width: 20)

            Text(title)
                .font(AppTypography.body)

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 15))
            } else {
                Button("Enable") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: isGranted)
    }

    @ViewBuilder
    private var modelSetupRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .frame(width: 20)

                if appState.phase == .downloadingModel {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Speech Model")
                                .font(AppTypography.body)
                            Spacer()
                            Text(verbatim: "\(Int(appState.downloadProgress * 100))%")
                                .font(AppTypography.codeCaption)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }

                        ProgressView(value: appState.downloadProgress)
                            .progressViewStyle(.linear)

                        HStack(spacing: 4) {
                            Text(verbatim: ByteCountFormatter.string(
                                fromByteCount: Int64(Double(appState.modelExpectedByteCount) * appState.downloadProgress),
                                countStyle: .file
                            ))
                            Text("of \(appState.modelExpectedSizeText)")
                            Text("·")
                            Text(appState.modelDownloadETAStatusText)
                        }
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                } else if appState.phase == .loading {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech Model")
                            .font(AppTypography.body)

                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Setting up...")
                                .font(AppTypography.caption)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }
                    }
                } else {
                    Text("Speech Model")
                        .font(AppTypography.body)

                    Spacer()

                    modelStatusView
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if appState.phase == .error {
                VStack(alignment: .leading, spacing: 10) {
                    if let error = appState.lastError, !error.isEmpty {
                        Text(error)
                            .font(AppTypography.caption)
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 10) {
                        Button("Retry Download") {
                            appState.startModelDownload()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Remove Files") {
                            appState.deleteModel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var modelStatusView: some View {
        if appState.phase == .ready || appState.phase == .recording || appState.phase == .transcribing {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
        } else if appState.phase == .error {
            Text("Failed")
                .font(AppTypography.caption)
                .foregroundStyle(.red)
        } else if appState.phase == .downloadingModel {
            Text("\(Int(appState.downloadProgress * 100))%")
                .font(AppTypography.codeCaption)
                .foregroundStyle(MainWindowPalette.secondaryText)
        } else if appState.phase == .loading {
            ProgressView()
                .controlSize(.small)
        } else {
            Button(appState.phase == .error ? "Retry" : "Download") {
                appState.startModelDownload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Practice

    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try your first dictation")
                .font(AppTypography.pageTitle)

            Text("Hold \(appState.hotkeyConfiguration.displayString) and speak")
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)

            practiceTextArea
                .padding(.top, 4)

            if appState.isOnboardingPracticeRecording {
                practiceStatusLabel("Listening...", color: .accentColor)
            } else if appState.isOnboardingPracticeProcessing {
                practiceStatusLabel("Transcribing...", color: .accentColor)
            } else if let result = appState.onboardingPracticeResult {
                practiceStatusLabel(result.message, color: result.severity.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var practiceTextArea: some View {
        let isActive = appState.isOnboardingPracticeRecording

        return ScrollView {
            Text(appState.onboardingPracticeText.isEmpty
                 ? "Your dictation will appear here..."
                 : appState.onboardingPracticeText)
                .font(AppTypography.body)
                .foregroundStyle(appState.onboardingPracticeText.isEmpty
                    ? MainWindowPalette.tertiaryText
                    : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MainWindowPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? Color.accentColor : MainWindowPalette.cardStroke,
                        lineWidth: isActive ? 1.5 : 1)
        )
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
    }

    // MARK: - Navigation

    @ViewBuilder
    private var navigationButtons: some View {
        HStack {
            if step == .setup {
                Button {
                    appState.goBackOnboarding()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(AppTypography.body)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(MainWindowPalette.secondaryText)
            }

            Spacer()

            switch step {
            case .welcome:
                Button("Get Started") {
                    appState.advanceOnboarding()
                }
                .buttonStyle(.borderedProminent)

            case .setup:
                Button("Continue") {
                    appState.advanceOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.isOnboardingSetupComplete)

            case .practice:
                HStack(spacing: 10) {
                    Button("Skip") {
                        appState.finishOnboarding()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.phase == .recording || appState.phase == .transcribing)

                    Button("Finish") {
                        appState.finishOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.phase == .recording || appState.phase == .transcribing)
                }
            }
        }
    }
}
