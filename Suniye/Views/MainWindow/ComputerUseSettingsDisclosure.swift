import SwiftUI

struct ComputerUseSettingsDisclosure: View {
    @Bindable var coordinator: ComputerUseCoordinator
    let openModelSettings: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                settingsRow(
                    title: "Model",
                    detail: coordinator.modelID ?? "Not configured",
                    isReady: coordinator.isModelConfigured,
                    buttonTitle: "Model Settings",
                    action: openModelSettings
                )
                Divider().padding(.vertical, 10)
                permissionRow(
                    title: "Accessibility",
                    detail: "Reads controls and sends input to apps.",
                    state: coordinator.permissionSnapshot.accessibility,
                    request: coordinator.requestAccessibility,
                    openSettings: {
                        coordinator.openPermissionSettings(.accessibility)
                    }
                )
                Divider().padding(.vertical, 10)
                permissionRow(
                    title: "Screen Recording",
                    detail: "Captures the selected app window for visual context.",
                    state: coordinator.permissionSnapshot.screenRecording,
                    request: coordinator.requestScreenRecording,
                    openSettings: {
                        coordinator.openPermissionSettings(.screenRecording)
                    }
                )
            }
            .padding(.top, 14)
        } label: {
            Label("Computer Use settings", systemImage: "slider.horizontal.3")
                .font(AppTypography.bodyMedium)
        }
        .padding(16)
        .background(MainWindowPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
        )
    }

    private func permissionRow(
        title: String,
        detail: String,
        state: ComputerUsePermissionState,
        request: @escaping () async -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        settingsRow(
            title: title,
            detail: detail,
            isReady: state == .granted,
            buttonTitle: state == .granted ? nil : "Grant Access",
            secondaryButtonTitle: state == .granted ? nil : "Open Settings",
            secondaryAction: openSettings,
            action: {
                Task { await request() }
            }
        )
    }

    private func settingsRow(
        title: String,
        detail: String,
        isReady: Bool,
        buttonTitle: String?,
        secondaryButtonTitle: String? = nil,
        secondaryAction: @escaping () -> Void = {},
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReady ? Color.green : MainWindowPalette.tertiaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.bodyMedium)
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            Spacer(minLength: 12)
            if let secondaryButtonTitle {
                Button(secondaryButtonTitle, action: secondaryAction)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(coordinator.isBusy)
            }
            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(coordinator.isBusy)
            }
        }
    }
}
