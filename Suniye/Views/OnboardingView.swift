import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState

    private var step: OnboardingStep {
        appState.activeOnboardingStep ?? .welcome
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(currentStep: step)
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Rectangle()
                .fill(MainWindowPalette.divider)
                .frame(height: 1)

            HStack(spacing: 0) {
                leftColumn
                    .frame(width: 320)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .padding(32)

                Rectangle()
                    .fill(MainWindowPalette.divider)
                    .frame(width: 1)

                rightColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(32)
                    .background(MainWindowPalette.selectedFill.opacity(0.45))
            }
        }
        .background(MainWindowPalette.windowBackground)
        .onAppear {
            appState.refreshPermissionStatus()
        }
        .onChange(of: appState.activeOnboardingStep) { _, _ in
            appState.refreshPermissionStatus()
        }
    }

    @ViewBuilder
    private var leftColumn: some View {
        switch step {
        case .welcome:
            WelcomeView {
                appState.advanceOnboarding()
            }
        case .setup:
            VStack(alignment: .leading, spacing: 18) {
                Button {
                    appState.goBackOnboarding()
                } label: {
                    Label("Back", systemImage: "arrow.left")
                        .font(AppTypography.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MainWindowPalette.secondaryText)

                Text("Set up Suniye")
                    .font(AppTypography.pageTitle)

                Text("Grant the required permissions and download the offline model. You only need to do this once.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    OnboardingChecklistRow(
                        title: "Accessibility permission",
                        isComplete: appState.hasAccessibilityPermission
                    )
                    OnboardingChecklistRow(
                        title: "Microphone permission",
                        isComplete: appState.hasMicPermission
                    )
                    OnboardingChecklistRow(
                        title: "Offline model ready",
                        isComplete: appState.isOnboardingSetupComplete
                    )
                }

                Spacer()

                Button("Continue") {
                    appState.advanceOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.isOnboardingSetupComplete)
            }
        case .practice:
            VStack(alignment: .leading, spacing: 18) {
                Text("Try your first dictation")
                    .font(AppTypography.pageTitle)

                Text("Hold \(appState.hotkeyConfiguration.displayString) and say a short sentence. We'll preview the result here instead of pasting it anywhere.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let result = appState.onboardingPracticeResult {
                    Text(result.message)
                        .font(AppTypography.caption)
                        .foregroundStyle(result.severity.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

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

    @ViewBuilder
    private var rightColumn: some View {
        switch step {
        case .welcome:
            welcomePanel
        case .setup:
            setupPanel
        case .practice:
            practicePanel
        }
    }

    private var welcomePanel: some View {
        VStack(spacing: 18) {
            SurfaceCard(padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How it works")
                        .font(AppTypography.bodyMedium)

                    HStack(spacing: 10) {
                        OnboardingShortcutChip(label: "Fn / Globe")
                        Image(systemName: "waveform")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        OnboardingShortcutChip(label: "Speak")
                        Image(systemName: "arrow.right")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        OnboardingShortcutChip(label: "Paste")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        OnboardingInstructionRow(
                            title: "Hold the shortcut",
                            detail: "Use the Fn/Globe key to start dictation from anywhere."
                        )
                        OnboardingInstructionRow(
                            title: "Speak naturally",
                            detail: "Suniye captures audio locally and transcribes it on-device."
                        )
                        OnboardingInstructionRow(
                            title: "Release to paste",
                            detail: "Your spoken text is inserted into the app you were already using."
                        )
                    }
                }
            }
            .frame(maxWidth: 480)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingSetupCard(
                title: "Accessibility",
                detail: "Lets Suniye paste transcribed text into the focused app.",
                statusText: appState.hasAccessibilityPermission ? "Granted" : "Required",
                statusColor: appState.hasAccessibilityPermission ? .green : .orange
            ) {
                if !appState.hasAccessibilityPermission {
                    HStack(spacing: 8) {
                        Button("Allow") {
                            appState.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open Settings") {
                            appState.openAccessibilityPrivacySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            OnboardingSetupCard(
                title: "Microphone",
                detail: "Required to capture your dictation audio.",
                statusText: appState.hasMicPermission ? "Granted" : "Required",
                statusColor: appState.hasMicPermission ? .green : .orange
            ) {
                if !appState.hasMicPermission {
                    HStack(spacing: 8) {
                        Button("Allow") {
                            appState.requestMicrophonePermission()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open Settings") {
                            appState.openMicrophonePrivacySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            OnboardingSetupCard(
                title: "Offline Model",
                detail: "Downloads the local speech model Suniye needs for transcription.",
                statusText: modelStatusText,
                statusColor: modelStatusColor,
                supplementalText: appState.phase == .downloadingModel ? nil : modelSupplementalText
            ) {
                if appState.phase == .downloadingModel {
                    modelDownloadSupplementalView
                    ProgressView(value: appState.downloadProgress)
                        .progressViewStyle(.linear)
                } else if appState.phase == .loading, appState.isModelInstalled {
                    ProgressView()
                        .controlSize(.small)
                } else if !appState.isModelInstalled {
                    Button(modelActionTitle) {
                        appState.startModelDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.phase == .downloadingModel)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 520, maxHeight: .infinity, alignment: .top)
    }

    private var practicePanel: some View {
        VStack(spacing: 16) {
            SurfaceCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Try it in this box")
                        .font(AppTypography.bodyMedium)

                    Text("Use \(appState.hotkeyConfiguration.displayString), say a short sentence, then release. Your dictation will appear below.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if appState.isOnboardingPracticeRecording {
                        Text("Listening...")
                            .font(AppTypography.subheadlineSemibold)
                            .foregroundStyle(Color.accentColor)
                    } else if appState.isOnboardingPracticeProcessing {
                        Text("Transcribing...")
                            .font(AppTypography.subheadlineSemibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            SurfaceCard(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preview")
                        .font(AppTypography.bodyMedium)

                    ScrollView {
                        Text(appState.onboardingPracticeText.isEmpty
                             ? "Your first dictation will appear here."
                             : appState.onboardingPracticeText)
                            .font(AppTypography.body)
                            .foregroundStyle(appState.onboardingPracticeText.isEmpty ? MainWindowPalette.secondaryText : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(minHeight: 170, maxHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MainWindowPalette.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 520, maxHeight: .infinity, alignment: .top)
    }

    private var modelStatusText: String {
        switch appState.phase {
        case .downloadingModel:
            return "Downloading"
        case .loading where appState.isModelInstalled:
            return "Validating"
        case .ready where appState.isModelInstalled:
            return "Ready"
        case .error where !appState.isModelInstalled:
            return "Failed"
        default:
            return appState.isModelInstalled ? "Ready" : "Required"
        }
    }

    private var modelStatusColor: Color {
        switch appState.phase {
        case .downloadingModel, .loading:
            return .accentColor
        case .ready where appState.isModelInstalled:
            return .green
        case .error where !appState.isModelInstalled:
            return .red
        default:
            return appState.isModelInstalled ? .green : .orange
        }
    }

    private var modelSupplementalText: String? {
        switch appState.phase {
        case .downloadingModel:
            return appState.modelDownloadProgressLabel
        case .loading where appState.isModelInstalled:
            return "Preparing the local recognizer."
        case .error where !appState.isModelInstalled:
            return appState.lastError
        default:
            return appState.modelPrimaryActionDetail
        }
    }

    private var modelActionTitle: String {
        appState.phase == .error ? "Retry Download" : "Download Model"
    }

    private var modelDownloadSupplementalView: some View {
        VStack(alignment: .leading, spacing: 2) {
            (
                Text(verbatim: "\(Int(appState.downloadProgress * 100))%")
                    .font(AppTypography.codeCaption)
                + Text(" downloaded • ")
                    .font(AppTypography.caption)
                + Text(verbatim: ByteCountFormatter.string(
                    fromByteCount: Int64(Double(appState.modelExpectedByteCount) * appState.downloadProgress),
                    countStyle: .file
                ))
                    .font(AppTypography.codeCaption)
                + Text(" of ")
                    .font(AppTypography.caption)
                + Text(verbatim: appState.modelExpectedSizeText)
                    .font(AppTypography.codeCaption)
            )
            .foregroundStyle(MainWindowPalette.secondaryText)

            Text(appState.modelDownloadETAStatusText)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OnboardingProgressHeader: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 14) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                HStack(spacing: 8) {
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : MainWindowPalette.cardStroke)
                        .frame(width: 7, height: 7)

                    Text(step.title)
                        .font(AppTypography.subheadlineSemibold)
                        .foregroundStyle(step.rawValue <= currentStep.rawValue ? Color.primary : MainWindowPalette.secondaryText)
                }

                if step != .practice {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.accentColor.opacity(0.5) : MainWindowPalette.cardStroke)
                        .frame(width: 28, height: 1)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingSetupCard<Actions: View>: View {
    let title: String
    let detail: String
    let statusText: String
    let statusColor: Color
    let supplementalText: String?
    let actions: Actions

    init(
        title: String,
        detail: String,
        statusText: String,
        statusColor: Color,
        supplementalText: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.detail = detail
        self.statusText = statusText
        self.statusColor = statusColor
        self.supplementalText = supplementalText
        self.actions = actions()
    }

    var body: some View {
        SurfaceCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(AppTypography.bodyMedium)
                        Text(detail)
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    OnboardingStatusBadge(text: statusText, color: statusColor)
                }

                if let supplementalText, !supplementalText.isEmpty {
                    Text(supplementalText)
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actions
            }
        }
    }
}

private struct OnboardingStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

private struct OnboardingShortcutChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(AppTypography.codeCalloutSemibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(MainWindowPalette.cardBackground)
            )
            .overlay(
                Capsule()
                    .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
            )
    }
}

private struct OnboardingChecklistRow: View {
    let title: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? Color.green : MainWindowPalette.secondaryText)
            Text(title)
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
    }
}

private struct OnboardingInstructionRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTypography.subheadlineSemibold)
            Text(detail)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
