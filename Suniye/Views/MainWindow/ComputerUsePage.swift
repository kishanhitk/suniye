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
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            composer
        }
        .background(MainWindowPalette.windowBackground)
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
        HStack(spacing: 12) {
            DetailPageTitle(title: "Computer Use")
            Spacer(minLength: 12)
            Button {
                coordinator.clearConversation()
            } label: {
                Label("New conversation", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .disabled(coordinator.isBusy || coordinator.conversation.isEmpty)
        }
        .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
        .padding(.vertical, 16)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if coordinator.conversation.isEmpty, !coordinator.isBusy {
                        ComputerUseEmptyConversation()
                    }

                    ForEach(coordinator.conversation) { message in
                        ComputerUseChatMessageRow(message: message)
                            .id(message.id)
                    }

                    if coordinator.phase == .runningAgent {
                        ComputerUseWorkingRow(
                            applicationName: coordinator.selectedApplication?.displayName,
                            stop: coordinator.cancel
                        )
                        .id("computer-use-working")
                    }

                    ComputerUseDetailsView(
                        coordinator: coordinator,
                        remoteModelConfiguration: remoteModelConfiguration
                    )
                    .padding(.top, 10)
                }
                .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
                .padding(.vertical, 28)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: coordinator.conversation.count) { _, _ in
                scrollToLatest(using: proxy)
            }
            .onChange(of: coordinator.phase) { _, phase in
                guard phase == .runningAgent else {
                    return
                }
                scrollToLatest(using: proxy)
            }
        }
    }

    private var composer: some View {
        ComputerUseComposer(
            instruction: $coordinator.agentInstruction,
            isWorking: coordinator.phase == .runningAgent,
            canSend: coordinator.canRunAgent,
            readinessMessage: readinessMessage,
            send: coordinator.startAgent,
            stop: coordinator.cancel
        )
    }

    private var readinessMessage: String? {
        if coordinator.isVoiceTaskPending {
            return "Voice task captured. Computer Use is preparing."
        }
        if !coordinator.isModelConfigured {
            return "Connect an API endpoint in Model settings."
        }
        if !coordinator.permissionSnapshot.canReadAccessibility
            || !coordinator.permissionSnapshot.canCaptureScreen {
            return "Grant Accessibility and Screen Recording below."
        }
        return nil
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            if coordinator.phase == .runningAgent {
                proxy.scrollTo("computer-use-working", anchor: .bottom)
            } else if let lastMessage = coordinator.conversation.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

private struct ComputerUseEmptyConversation: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("What should I do on your Mac?")
                .font(AppTypography.pageTitle)
            Text("Ask with text or hold your dictation hotkey and speak. You can follow up in the same conversation.")
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct ComputerUseChatMessageRow: View {
    let message: ComputerUseConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 72)
            } else {
                assistantMark
            }

            Text(message.text)
                .font(AppTypography.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(message.role == .user ? 12 : 0)
                .background {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(MainWindowPalette.selectedFill)
                    }
                }

            if message.role == .assistant {
                Spacer(minLength: 72)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var assistantMark: some View {
        Image(systemName: "cursorarrow.motionlines")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.accentColor))
    }
}

private struct ComputerUseWorkingRow: View {
    let applicationName: String?
    let stop: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("Working")
                    .font(AppTypography.bodyMedium)
                Text(applicationName.map { "Using \($0)" } ?? "Choosing an app and reading its current state")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            Spacer(minLength: 12)
            Button("Stop", action: stop)
                .buttonStyle(.bordered)
        }
        .padding(.leading, 38)
    }
}

private struct ComputerUseComposer: View {
    @Binding var instruction: String
    let isWorking: Bool
    let canSend: Bool
    let readinessMessage: String?
    let send: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let readinessMessage {
                Text(readinessMessage)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $instruction)
                    .font(AppTypography.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 38, maxHeight: 86)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .disabled(isWorking)

                Button(action: isWorking ? stop : send) {
                    Image(systemName: isWorking ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(buttonEnabled ? Color.accentColor : Color.secondary.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!buttonEnabled)
                .help(isWorking ? "Stop" : "Send")
                .padding(.bottom, 8)
                .padding(.trailing, 8)
            }
            .background(MainWindowPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
            )

            Text("Computer Use can make mistakes. Keep an eye on important actions.")
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
        }
        .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private var buttonEnabled: Bool {
        isWorking || (canSend && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
