import AppKit
import SwiftUI

struct ComputerUsePage: View {
    @Bindable var coordinator: ComputerUseCoordinator
    let remoteModelConfiguration: ComputerUseRemoteModelConfiguration?
    let onVoiceTaskHandlerChange: ((any ComputerUseVoiceTaskHandling)?) -> Void

    init(
        coordinator: ComputerUseCoordinator,
        remoteModelConfiguration: ComputerUseRemoteModelConfiguration? = nil,
        onVoiceTaskHandlerChange: @escaping ((any ComputerUseVoiceTaskHandling)?) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.remoteModelConfiguration = remoteModelConfiguration
        self.onVoiceTaskHandlerChange = onVoiceTaskHandlerChange
    }

    var body: some View {
        DetailScrollContainer {
            header

            if let errorMessage = coordinator.errorMessage {
                InlineStatusBanner(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: coordinator.phaseTitle,
                    detail: errorMessage,
                    progress: nil
                )
            } else if coordinator.phase == .observing {
                InlineStatusBanner(
                    icon: "eye",
                    tint: .accentColor,
                    title: coordinator.phaseTitle,
                    detail: "Reading the selected app. No input event will be posted.",
                    progress: nil
                )
            } else if coordinator.phase == .runningAgent {
                InlineStatusBanner(
                    icon: "sparkles",
                    tint: .accentColor,
                    title: coordinator.phaseTitle,
                    detail: "Reading the selected app and applying the next model action automatically.",
                    progress: nil
                )
            } else if coordinator.phase == .agentCompleted,
                      let result = coordinator.agentResult {
                InlineStatusBanner(
                    icon: result.phase == .completed ? "checkmark.circle.fill" : "info.circle",
                    tint: result.phase == .completed ? .green : .orange,
                    title: coordinator.phaseTitle,
                    detail: result.message,
                    progress: nil
                )
            }

            permissions
            targetSelection
            ComputerUseAgentPanel(
                coordinator: coordinator,
                remoteModelConfiguration: remoteModelConfiguration
            )
            observationPreview

            SurfaceCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                    Text("Actions run automatically after you start a task. Accessibility and Screen Recording permissions still apply.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            onVoiceTaskHandlerChange(coordinator)
            coordinator.configureRemoteModel(remoteModelConfiguration)
            coordinator.start()
        }
        .onChange(of: remoteModelConfiguration) { _, configuration in
            coordinator.configureRemoteModel(configuration)
        }
        .onDisappear {
            onVoiceTaskHandlerChange(nil)
            coordinator.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                DetailPageTitle(title: "Computer Use")
                Text("Inspect an app and run a task automatically.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                coordinator.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.isBusy)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Permissions")

            SurfaceCard {
                VStack(spacing: 0) {
                    ComputerUsePermissionRow(
                        title: "Accessibility",
                        detail: "Required to read app windows and controls.",
                        state: coordinator.permissionSnapshot.accessibility,
                        action: coordinator.requestAccessibility
                    )

                    CardDivider()
                        .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                    ComputerUsePermissionRow(
                        title: "Screen Recording",
                        detail: "Required to capture the app window for the model.",
                        state: coordinator.permissionSnapshot.screenRecording,
                        action: coordinator.requestScreenRecording
                    )
                }
            }
        }
    }

    private var targetSelection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Starting app (optional)")

            SurfaceCard(padding: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    if coordinator.applications.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "macwindow.on.rectangle")
                                .foregroundStyle(MainWindowPalette.secondaryText)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No running apps were found.")
                                    .font(AppTypography.body)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                                Text("The agent can choose and launch an app from the task.")
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.tertiaryText)
                            }
                            Spacer(minLength: 8)
                            Button("Refresh", action: coordinator.refresh)
                                .buttonStyle(.bordered)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Text("Starting app")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
                            NativePopupPicker(
                                items: coordinator.applicationIDs,
                                selection: selectedApplicationBinding,
                                title: applicationTitle(for:)
                            )
                            .frame(maxWidth: 320)
                            .disabled(coordinator.isBusy)
                        }

                        if let application = coordinator.selectedApplication {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(application.displayName)
                                        .font(AppTypography.bodyMedium)
                                    if application.isActive {
                                        StatusPill(title: "Active", tint: .green)
                                    }
                                }

                                Text(application.bundleIdentifier)
                                    .font(AppTypography.codeCaption)
                                    .foregroundStyle(MainWindowPalette.tertiaryText)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Spacer(minLength: 12)

                        if coordinator.isBusy {
                            Button("Cancel", action: coordinator.cancel)
                                .buttonStyle(.bordered)
                        } else {
                            Button(
                                coordinator.phase == .observed ? "Capture Again" : "Capture Observation",
                                action: coordinator.observeSelectedApplication
                            )
                            .buttonStyle(.borderedProminent)
                            .disabled(!coordinator.canObserve)
                        }
                    }
                }
            }
        }
    }

    private var observationPreview: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Observation")

            if let observation = coordinator.observation {
                ComputerUseObservationPreview(observation: observation)
            } else {
                SurfaceCard {
                    VStack(spacing: 12) {
                        Image(systemName: "eye")
                            .font(AppTypography.emptyIcon)
                            .foregroundStyle(Color.secondary.opacity(0.72))
                        Text("No observation yet")
                            .font(AppTypography.bodyMedium)
                        Text("Select an app and capture its current state.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
        }
    }

    private var selectedApplicationBinding: Binding<String> {
        Binding(
            get: { coordinator.selectedApplicationID ?? "" },
            set: { coordinator.selectApplication($0) }
        )
    }

    private func applicationTitle(for identifier: String) -> String {
        coordinator.applications.first { $0.id == identifier }?.displayName ?? identifier
    }

}

private struct ComputerUsePermissionRow: View {
    let title: String
    let detail: String
    let state: ComputerUsePermissionState
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(AppTypography.body)
                    Image(systemName: state.icon)
                        .foregroundStyle(state.tint)
                }

                Text(detail)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if state != .granted {
                Button(state == .unavailable ? "Unavailable" : "Request Access", action: action)
                    .buttonStyle(.bordered)
                    .disabled(state == .unavailable)
            } else {
                Text("Granted")
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct ComputerUseObservationPreview: View {
    let observation: ComputerUseObservation

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SurfaceCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(observation.target.application.displayName)
                            .font(AppTypography.bodyMedium)
                        Spacer(minLength: 8)
                    }
                }
            }

            if let screenshot = observation.screenshot,
               let image = NSImage(data: screenshot.data) {
                SurfaceCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Screenshot · \(screenshot.width) × \(screenshot.height)")
                            .font(AppTypography.subheadlineSemibold)

                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .background(MainWindowPalette.editorBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            SurfaceCard(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Accessibility text")
                            .font(AppTypography.subheadlineSemibold)
                        Spacer(minLength: 8)
                        if observation.accessibility.wasTruncated {
                            StatusPill(title: "Truncated", tint: .orange)
                        }
                    }

                    ScrollView(.vertical) {
                        Text(observation.accessibility.text.isEmpty ? "No text was exposed." : observation.accessibility.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180, maxHeight: 320)
                }
            }
        }
    }

}

private extension ComputerUsePermissionState {
    var icon: String {
        switch self {
        case .granted:
            return "checkmark.circle.fill"
        case .notGranted:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .granted:
            return .green
        case .notGranted:
            return .orange
        case .unavailable:
            return MainWindowPalette.secondaryText
        }
    }
}
