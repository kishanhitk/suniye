import SwiftUI

struct ComputerUseAgentPanel: View {
    @Bindable var coordinator: ComputerUseCoordinator
    let remoteModelConfiguration: ComputerUseRemoteModelConfiguration?

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Agent task")

            SurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    modelStatus

                    Text("The agent sends the current Accessibility state and screenshot to the configured endpoint.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        "Hold your dictation hotkey, speak a task, and release. The agent starts automatically after transcription.",
                        systemImage: "mic"
                    )
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                    if coordinator.isVoiceTaskPending {
                        Label(
                            "Voice task captured; waiting for Computer Use to become ready.",
                            systemImage: "hourglass"
                        )
                        .font(AppTypography.subheadline)
                        .foregroundStyle(.orange)
                    }

                    TextEditor(text: $coordinator.agentInstruction)
                        .font(AppTypography.body)
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(MainWindowPalette.editorBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
                        )
                        .disabled(coordinator.isBusy)

                    HStack(alignment: .top, spacing: 12) {
                        Spacer(minLength: 12)

                        Button {
                            coordinator.startAgent()
                        } label: {
                            Label("Run agent task", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!coordinator.canRunAgent || instructionIsEmpty)
                    }

                    if let question = coordinator.agentResult?.question {
                        CardDivider()
                        Label(question, systemImage: "questionmark.circle")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var instructionIsEmpty: Bool {
        coordinator.agentInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modelStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: remoteModelConfiguration == nil ? "link.badge.plus" : "checkmark.circle.fill")
                .foregroundStyle(remoteModelConfiguration == nil ? .orange : .green)

            VStack(alignment: .leading, spacing: 4) {
                if let configuration = remoteModelConfiguration {
                    Text("Connected model: \(configuration.modelID)")
                        .font(AppTypography.bodyMedium)
                    Text("API endpoint configured in Model settings")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                } else {
                    Text("No remote model connected")
                        .font(AppTypography.bodyMedium)
                    Text("Select API Endpoint in Model settings and save an API key.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
            }

            Spacer(minLength: 12)
        }
    }
}
