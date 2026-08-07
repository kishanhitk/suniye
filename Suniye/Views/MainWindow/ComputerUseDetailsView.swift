import AppKit
import SwiftUI

struct ComputerUseDetailsView: View {
    @Bindable var coordinator: ComputerUseCoordinator
    let remoteModelConfiguration: ComputerUseRemoteModelConfiguration?

    @State private var settingsExpanded = false
    @State private var debugExpanded = false

    var body: some View {
        VStack(spacing: 10) {
            if let errorMessage = coordinator.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coordinator.phaseTitle)
                            .font(AppTypography.bodyMedium)
                        Text(errorMessage)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                    Spacer(minLength: 12)
                }
                .padding(.bottom, 4)
            }

            DisclosureGroup(isExpanded: $settingsExpanded) {
                settings
                    .padding(.top, 14)
            } label: {
                Label("Computer Use settings", systemImage: "slider.horizontal.3")
                    .font(AppTypography.bodyMedium)
            }

            DisclosureGroup(isExpanded: $debugExpanded) {
                debugObservation
                    .padding(.top, 14)
            } label: {
                Label("Observation details", systemImage: "ladybug")
                    .font(AppTypography.bodyMedium)
            }
        }
        .padding(14)
        .background(MainWindowPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
        )
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelStatus
            Divider()
            permissions
            Divider()
            startingApplication
        }
    }

    private var modelStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: remoteModelConfiguration == nil ? "link.badge.plus" : "checkmark.circle.fill")
                .foregroundStyle(remoteModelConfiguration == nil ? .orange : .green)
            VStack(alignment: .leading, spacing: 3) {
                Text(remoteModelConfiguration.map { "Connected to \($0.modelID)" } ?? "No model connected")
                    .font(AppTypography.bodyMedium)
                Text(remoteModelConfiguration == nil
                    ? "Add an API endpoint, model, and key in Model settings."
                    : "The current screenshot and Accessibility state are sent to this endpoint.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            Spacer(minLength: 12)
        }
    }

    private var permissions: some View {
        VStack(spacing: 12) {
            ComputerUsePermissionRow(
                title: "Accessibility",
                detail: "Read controls and perform input.",
                state: coordinator.permissionSnapshot.accessibility,
                action: coordinator.requestAccessibility
            )
            ComputerUsePermissionRow(
                title: "Screen Recording",
                detail: "Capture the current app window.",
                state: coordinator.permissionSnapshot.screenRecording,
                action: coordinator.requestScreenRecording
            )
        }
    }

    private var startingApplication: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Starting app")
                        .font(AppTypography.bodyMedium)
                    Text("Optional. The agent can choose from the task.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
                Spacer(minLength: 12)
                NativePopupPicker(
                    items: [""] + coordinator.applicationIDs,
                    selection: selectedApplicationBinding,
                    title: applicationTitle(for:)
                )
                .frame(maxWidth: 260)
                .disabled(coordinator.isBusy)
            }

            HStack {
                Spacer()
                Button("Refresh apps", action: coordinator.refresh)
                    .buttonStyle(.bordered)
                    .disabled(coordinator.isBusy)
            }
        }
    }

    @ViewBuilder
    private var debugObservation: some View {
        if let observation = coordinator.observation {
            ComputerUseObservationDetails(
                observation: observation,
                canCapture: coordinator.canObserve,
                capture: coordinator.observeSelectedApplication
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("No observation captured")
                    .font(AppTypography.bodyMedium)
                Text("Choose a starting app to inspect its screenshot and Accessibility text without running a task.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                Button("Capture observation", action: coordinator.observeSelectedApplication)
                    .buttonStyle(.bordered)
                    .disabled(!coordinator.canObserve)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedApplicationBinding: Binding<String> {
        Binding(
            get: { coordinator.selectedApplicationID ?? "" },
            set: { coordinator.selectApplication($0) }
        )
    }

    private func applicationTitle(for identifier: String) -> String {
        guard !identifier.isEmpty else {
            return "Let agent choose"
        }
        return coordinator.applications.first { $0.id == identifier }?.displayName ?? identifier
    }
}

private struct ComputerUsePermissionRow: View {
    let title: String
    let detail: String
    let state: ComputerUsePermissionState
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: state.icon)
                .foregroundStyle(state.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.bodyMedium)
                Text(detail)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            Spacer(minLength: 12)
            if state != .granted {
                Button(state == .unavailable ? "Unavailable" : "Grant", action: action)
                    .buttonStyle(.bordered)
                    .disabled(state == .unavailable)
            }
        }
    }
}

private struct ComputerUseObservationDetails: View {
    let observation: ComputerUseObservation
    let canCapture: Bool
    let capture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(observation.target.application.displayName)
                        .font(AppTypography.bodyMedium)
                    Text("Generation \(observation.generation)")
                        .font(AppTypography.codeCaption)
                        .foregroundStyle(MainWindowPalette.tertiaryText)
                }
                Spacer()
            }

            if let screenshot = observation.screenshot,
               let image = NSImage(data: screenshot.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .background(MainWindowPalette.editorBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Accessibility text")
                        .font(AppTypography.subheadlineSemibold)
                    Spacer()
                    if observation.accessibility.wasTruncated {
                        StatusPill(title: "Truncated", tint: .orange)
                    }
                }
                ScrollView(.vertical) {
                    Text(observation.accessibility.text.isEmpty
                        ? "No text was exposed."
                        : observation.accessibility.text)
                        .font(AppTypography.codeCaption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("Capture again", action: capture)
                    .buttonStyle(.bordered)
                    .disabled(!canCapture)
            }
        }
    }
}

private extension ComputerUsePermissionState {
    var icon: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .notGranted: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .granted: .green
        case .notGranted: .orange
        case .unavailable: MainWindowPalette.secondaryText
        }
    }
}
