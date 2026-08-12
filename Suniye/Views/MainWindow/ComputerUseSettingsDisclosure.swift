import SwiftUI

struct ComputerUseSettingsDisclosure: View {
    @Bindable var coordinator: ComputerUseCoordinator
    @Bindable var modelSettings: ComputerUseModelSettingsController

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                modelConfiguration
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

    private var modelConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: modelSettings.isReady ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(modelSettings.isReady ? Color.green : MainWindowPalette.tertiaryText)
                Text("Model")
                    .font(AppTypography.bodyMedium)
                Spacer()
                Picker("Provider", selection: $modelSettings.settings.provider) {
                    ForEach(ComputerUseModelProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            labeledField("Model ID") {
                TextField("gpt-5.6-luna", text: $modelSettings.settings.modelID)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField("API endpoint") {
                if modelSettings.settings.provider == .custom {
                    TextField(
                        "https://example.com/v1/chat/completions",
                        text: $modelSettings.settings.customEndpointURLString
                    )
                    .textFieldStyle(.roundedBorder)
                } else {
                    Text(modelSettings.settings.endpointURLString)
                        .font(AppTypography.codeBody)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            labeledField("API key") {
                HStack(spacing: 8) {
                    SecureField(
                        modelSettings.hasAPIKey ? "Saved" : "Required",
                        text: $modelSettings.apiKeyDraft
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        modelSettings.saveAPIKey()
                    }
                    .disabled(modelSettings.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if modelSettings.hasAPIKey {
                        Button("Clear", action: modelSettings.clearAPIKey)
                    }
                }
            }

            if let message = modelStatusMessage {
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(modelStatusIsError ? Color.red : MainWindowPalette.secondaryText)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Test connection") {
                    Task { await modelSettings.testConnection() }
                }
                .disabled(!modelSettings.isReady || modelSettings.connectionState == .testing)
            }
        }
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
            content()
        }
    }

    private var modelStatusMessage: String? {
        if let error = modelSettings.settings.modelValidationError
            ?? modelSettings.settings.endpointValidationError
            ?? modelSettings.credentialError {
            return error
        }
        switch modelSettings.connectionState {
        case .idle:
            return modelSettings.hasAPIKey ? "API key saved in Keychain." : "Enter an API key to enable Computer Use."
        case .testing:
            return "Testing connection…"
        case .connected:
            return "Connected."
        case let .failed(message):
            return message
        }
    }

    private var modelStatusIsError: Bool {
        if modelSettings.settings.modelValidationError != nil
            || modelSettings.settings.endpointValidationError != nil
            || modelSettings.credentialError != nil {
            return true
        }
        if case .failed = modelSettings.connectionState { return true }
        return false
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
