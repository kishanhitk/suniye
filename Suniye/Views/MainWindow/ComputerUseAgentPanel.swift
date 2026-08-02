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

                    Text("The agent sends accessibility text to the configured endpoint. A screenshot is sent only when you allow it below.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

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
                        Toggle(
                            "Allow screenshot upload",
                            isOn: Binding(
                                get: { coordinator.allowRemoteScreenshotUpload },
                                set: coordinator.setRemoteScreenshotUploadAllowed
                            )
                        )
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(remoteModelConfiguration == nil || coordinator.isBusy)

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
