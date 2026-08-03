import AppKit
import SwiftUI

struct ComputerUsePage: View {
    @Bindable var coordinator: ComputerUseCoordinator
    let remoteModelConfiguration: ComputerUseRemoteModelConfiguration?
    @State private var approvalToRemove: ComputerUseApprovalRecord?

    init(
        coordinator: ComputerUseCoordinator,
        remoteModelConfiguration: ComputerUseRemoteModelConfiguration? = nil
    ) {
        self.coordinator = coordinator
        self.remoteModelConfiguration = remoteModelConfiguration
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
                    detail: "Reading the selected window. No input event will be posted.",
                    progress: nil
                )
            } else if coordinator.phase == .activatingWindow {
                InlineStatusBanner(
                    icon: "macwindow.badge.plus",
                    tint: .accentColor,
                    title: coordinator.phaseTitle,
                    detail: "Bringing the selected window to the front before control starts.",
                    progress: nil
                )
            } else if coordinator.phase == .runningAgent {
                InlineStatusBanner(
                    icon: "sparkles",
                    tint: .accentColor,
                    title: coordinator.phaseTitle,
                    detail: "Reading the selected app and waiting for the next model decision. Approval is required before each action.",
                    progress: nil
                )
            } else if coordinator.phase == .acting {
                InlineStatusBanner(
                    icon: "hand.tap",
                    tint: .accentColor,
                    title: coordinator.phaseTitle,
                    detail: "Executing the approved action. Cancel is available.",
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
            } else if coordinator.phase == .actionCompleted,
                      let result = coordinator.lastActionResult {
                InlineStatusBanner(
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    title: coordinator.phaseTitle,
                    detail: result.action.summary,
                    progress: nil
                )
            }

            permissions
            alwaysAllowedApprovals
            targetSelection
            ComputerUseAgentPanel(
                coordinator: coordinator,
                remoteModelConfiguration: remoteModelConfiguration
            )
            observationPreview

            if let request = coordinator.pendingApproval {
                ComputerUseApprovalCard(
                    request: request,
                    allow: coordinator.approvePendingAction(scope:),
                    deny: coordinator.denyPendingAction,
                    stop: coordinator.stopPendingAction
                )
            }

            ComputerUseActionPanel(coordinator: coordinator)

            SurfaceCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                    Text("Every bounded action requires your approval. Persistent scopes are controlled by app policy.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            coordinator.configureRemoteModel(remoteModelConfiguration)
            coordinator.start()
        }
        .onChange(of: remoteModelConfiguration) { _, configuration in
            coordinator.configureRemoteModel(configuration)
        }
        .onDisappear {
            coordinator.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                DetailPageTitle(title: "Computer Use")
                Text("Inspect a running app window and approve one controlled action at a time.")
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
                        detail: "Required to read the selected app's windows and controls.",
                        state: coordinator.permissionSnapshot.accessibility,
                        action: coordinator.requestAccessibility
                    )

                    CardDivider()
                        .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                    ComputerUsePermissionRow(
                        title: "Screen Recording",
                        detail: "Required to include a screenshot of the selected window.",
                        state: coordinator.permissionSnapshot.screenRecording,
                        action: coordinator.requestScreenRecording
                    )
                }
            }
        }
    }

    private var alwaysAllowedApprovals: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Always allowed")

            SurfaceCard {
                if coordinator.alwaysApprovals.isEmpty {
                    Text("No app actions are always allowed.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(coordinator.alwaysApprovals.enumerated()), id: \.element.id) { index, record in
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.applicationBundleIdentifier)
                                        .font(AppTypography.bodyMedium)
                                    Text(record.risk.title)
                                        .font(AppTypography.subheadline)
                                        .foregroundStyle(MainWindowPalette.secondaryText)
                                }
                                Spacer(minLength: 12)
                                Button("Remove") {
                                    approvalToRemove = record
                                }
                                .buttonStyle(.bordered)
                            }

                            if index < coordinator.alwaysApprovals.count - 1 {
                                CardDivider()
                                    .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove always-allowed action?",
            isPresented: Binding(
                get: { approvalToRemove != nil },
                set: { isPresented in
                    if !isPresented {
                        approvalToRemove = nil
                    }
                }
            )
        ) {
            if let record = approvalToRemove {
                Button("Remove", role: .destructive) {
                    coordinator.revokeAlwaysApproval(record)
                    approvalToRemove = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                approvalToRemove.map {
                    "Suniye will ask before using \($0.risk.title.lowercased()) in \($0.applicationBundleIdentifier) again."
                } ?? "Suniye will ask before the action again."
            )
        }
    }

    private var targetSelection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Starting context (optional)")

            SurfaceCard(padding: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    if coordinator.applications.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "macwindow.on.rectangle")
                                .foregroundStyle(MainWindowPalette.secondaryText)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No running app windows were found.")
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

                        if !coordinator.windows.isEmpty {
                            HStack(spacing: 12) {
                                Text("Window")
                                    .font(AppTypography.body)
                                Spacer(minLength: 12)
                                NativePopupPicker(
                                    items: coordinator.windowIDs,
                                    selection: selectedWindowBinding,
                                    title: windowTitle(for:)
                                )
                                .frame(maxWidth: 320)
                                .disabled(coordinator.isBusy)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(MainWindowPalette.tertiaryText)
                                Text("This is only the starting context. The agent can switch apps and windows during the task.")
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Button("Bring Forward", action: coordinator.activateSelectedWindow)
                                    .buttonStyle(.bordered)
                                    .disabled(coordinator.isBusy)
                            }
                        }
                    }

                    CardDivider()

                    HStack(spacing: 12) {
                        Toggle("Include screenshot", isOn: $coordinator.includeScreenshot)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(coordinator.isBusy)

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
                        Text("Select a running app window and capture its current state.")
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

    private var selectedWindowBinding: Binding<UInt32> {
        Binding(
            get: { coordinator.selectedWindowID ?? coordinator.windowIDs.first ?? 0 },
            set: { coordinator.selectWindow($0) }
        )
    }

    private func applicationTitle(for identifier: String) -> String {
        coordinator.applications.first { $0.id == identifier }?.displayName ?? identifier
    }

    private func windowTitle(for identifier: UInt32) -> String {
        guard let window = coordinator.windows.first(where: { $0.id == identifier }) else {
            return "Window \(identifier)"
        }
        let title = window.title?.isEmpty == false ? (window.title ?? "Untitled") : "Untitled"
        return "\(title) · \(window.id)"
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
                        if let title = observation.target.window.title {
                            Text("· \(title)")
                                .font(AppTypography.body)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }
                        Spacer(minLength: 8)
                        StatusPill(title: "Generation \(observation.generation)", tint: .accentColor)
                    }

                    HStack(spacing: 16) {
                        observationMeta(title: "Window", value: "\(observation.target.window.id)")
                        observationMeta(
                            title: "Bounds",
                            value: format(bounds: observation.target.window.bounds)
                        )
                        observationMeta(
                            title: "Elements",
                            value: "\(observation.accessibility.elements.count)"
                        )
                    }
                }
            }

            if let screenshot = observation.screenshot,
               let image = NSImage(data: screenshot.data) {
                SurfaceCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Screenshot · \(screenshot.width) × \(screenshot.height) · \(screenshot.id.prefix(8))")
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

    private func observationMeta(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
            Text(value)
                .font(AppTypography.codeCaption)
                .foregroundStyle(Color.primary)
        }
    }

    private func format(bounds: ComputerUseRect) -> String {
        "\(Int(bounds.width)) × \(Int(bounds.height))"
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
