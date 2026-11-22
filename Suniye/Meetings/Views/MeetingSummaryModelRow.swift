import SwiftUI

/// The model that writes meeting summaries. A hosted choice opens its sheet,
/// and the setting changes only when the user agrees there.
struct MeetingSummaryModelRow: View {
    let appState: AppState
    @State private var settingUpAPIEndpoint = false

    private var choice: MeetingSummaryModelChoice {
        appState.meetings.settings.summaryModel
    }

    var body: some View {
        ControlSettingRow(
            title: "Summary model",
            info: "Writes the summary after the transcript. API endpoint sends the transcript and your notes to that service."
        ) {
            HStack(spacing: 10) {
                if choice != .automatic {
                    Button("Options…") { setUp(choice) }
                }
                Picker("Summary model", selection: Binding(get: { choice }, set: setUp)) {
                    Text("Automatic").tag(MeetingSummaryModelChoice.automatic)
                    Divider()
                    Text("API endpoint").tag(MeetingSummaryModelChoice.apiEndpoint)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .sheet(isPresented: $settingUpAPIEndpoint) {
            APIEndpointSummarySheet(appState: appState)
        }
    }

    private func setUp(_ choice: MeetingSummaryModelChoice) {
        switch choice {
        case .automatic:
            appState.meetings.updateSettings { $0.summaryModel = .automatic }
        case .apiEndpoint:
            settingUpAPIEndpoint = true
        }
    }
}

/// The agreement and the model ID for summaries through the user's API
/// endpoint.
struct APIEndpointSummarySheet: View {
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var modelID: String
    @State private var editingEndpoint = false

    init(appState: AppState) {
        self.appState = appState
        _modelID = State(initialValue: appState.meetings.settings.apiSummaryModelID)
    }

    private var endpointHost: String? {
        appState.llmSettings.validatedEndpointURL?.host
    }

    private var validModelID: String? {
        LLMDefaults.normalizedModelId(modelID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API endpoint")
                    .font(AppTypography.cardTitle)
                Text("After each meeting, Suniye sends the transcript and your notes to this service to write the summary. Audio never leaves this Mac.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Endpoint")
                    .font(AppTypography.subheadlineSemibold)
                HStack(spacing: 8) {
                    Text(endpointHost ?? "No endpoint")
                        .font(AppTypography.codeBodyMedium)
                    Text(appState.hasLLMAPIKey ? "API key saved" : "No API key")
                        .foregroundStyle(MainWindowPalette.secondaryText)
                    Spacer(minLength: 12)
                    Button("Edit Endpoint…") { editingEndpoint = true }
                }
                Text("Magic Format uses the same endpoint and key.")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(AppTypography.subheadlineSemibold)
                TextField("gpt-6.1-sol or provider/model-id", text: $modelID)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.codeBodyMedium)
                if validModelID == nil, !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Enter a valid model name.", systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 12) {
                Spacer(minLength: 12)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use API Endpoint") {
                    guard let endpointHost, let validModelID else { return }
                    appState.meetings.updateSettings {
                        $0.summaryModel = .apiEndpoint
                        $0.apiSummaryModelID = validModelID
                        $0.apiSummaryAgreedHost = endpointHost
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(endpointHost == nil || validModelID == nil || !appState.hasLLMAPIKey)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(MainWindowPalette.windowBackground)
        .sheet(isPresented: $editingEndpoint) {
            APIEndpointSheet(appState: appState)
        }
    }
}
