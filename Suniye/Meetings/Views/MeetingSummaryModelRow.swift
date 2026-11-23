import SwiftUI

/// The model that writes meeting summaries. A hosted choice opens its sheet,
/// and the setting changes only when the user agrees there.
struct MeetingSummaryModelRow: View {
    let appState: AppState
    @State private var settingUpChatGPT = false
    @State private var settingUpAPIEndpoint = false

    private var choice: MeetingSummaryModelChoice {
        appState.meetings.settings.summaryModel
    }

    var body: some View {
        ControlSettingRow(.summaryModel) {
            HStack(spacing: 10) {
                if choice != .automatic {
                    Button("Options…") { setUp(choice) }
                }
                Picker("Summary model", selection: Binding(get: { choice }, set: setUp)) {
                    Text("Automatic").tag(MeetingSummaryModelChoice.automatic)
                    Divider()
                    Text("ChatGPT").tag(MeetingSummaryModelChoice.chatGPT)
                    Text("API endpoint").tag(MeetingSummaryModelChoice.apiEndpoint)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .sheet(isPresented: $settingUpChatGPT) {
            ChatGPTSummarySheet(setup: appState.chatGPTSetup, isChosen: choice == .chatGPT)
        }
        .sheet(isPresented: $settingUpAPIEndpoint) {
            APIEndpointSummarySheet(appState: appState)
        }
    }

    private func setUp(_ choice: MeetingSummaryModelChoice) {
        switch choice {
        case .automatic:
            appState.meetings.updateSettings { $0.summaryModel = .automatic }
        case .chatGPT:
            settingUpChatGPT = true
        case .apiEndpoint:
            settingUpAPIEndpoint = true
        }
    }
}

/// Connect ChatGPT, the agreement to send meeting text to OpenAI, and the
/// model for summaries.
struct ChatGPTSummarySheet: View {
    let setup: ChatGPTSummarySetup
    /// ChatGPT is the summary model now.
    let isChosen: Bool

    @Environment(\.dismiss) private var dismiss

    private var isConnected: Bool {
        if case .connected = setup.state {
            return true
        }
        return false
    }

    private var email: String? {
        if case let .connected(email) = setup.state {
            return email
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isConnected ? "ChatGPT" : "Connect ChatGPT")
                    .font(AppTypography.cardTitle)
                if isConnected {
                    Text(numbers: email.map { "Connected as \($0)" } ?? "Connected")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                } else if case .signInEnded = setup.state {
                    Text("Your ChatGPT sign-in ended.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
            }

            Text("After each meeting, Suniye sends the transcript and your notes to OpenAI to write the summary. Audio never leaves this Mac.")
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Text("Summaries use your ChatGPT plan.")
                    .foregroundStyle(MainWindowPalette.secondaryText)
                if isConnected {
                    Link("Manage usage", destination: ChatGPTPlanClient.usageURL)
                }
            }
            .font(AppTypography.subheadline)

            if isConnected {
                modelPicker
            }

            if setup.isWaitingForSignIn {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finish the sign-in in your browser.")
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
            }

            if let message = setup.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buttons
        }
        .padding(20)
        .frame(width: 480)
        .background(MainWindowPalette.windowBackground)
        .task { await setup.open() }
        .onDisappear { setup.cancelSignIn() }
    }

    /// The saved model alone when the list did not load.
    private var modelPicker: some View {
        HStack {
            Text("Model")
                .font(AppTypography.subheadlineSemibold)
            Spacer(minLength: 12)
            Picker("Model", selection: Binding(get: { setup.model }, set: { setup.choose(model: $0) })) {
                if setup.models.isEmpty {
                    Text(setup.model).tag(setup.model)
                }
                ForEach(setup.models) { model in
                    Text(model.displayName).tag(model.slug)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if isConnected {
                Button("Disconnect") {
                    Task { await setup.disconnect() }
                }
            }
            Spacer(minLength: 12)
            if setup.isWaitingForSignIn {
                Button("Cancel") { setup.cancelSignIn() }
                    .keyboardShortcut(.cancelAction)
            } else if isConnected {
                if isChosen {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Use ChatGPT") {
                        setup.useChatGPT()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue with ChatGPT") { setup.connect() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
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
            Text("API endpoint")
                .font(AppTypography.cardTitle)

            Text("After each meeting, Suniye sends the transcript and your notes to this service to write the summary. Audio never leaves this Mac.")
                .fixedSize(horizontal: false, vertical: true)

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
