import AppKit
import SwiftUI

struct ComputerUsePage: View {
    @Bindable var coordinator: ComputerUseCoordinator
    @Bindable var modelSettings: ComputerUseModelSettingsController
    let onPageActiveChange: (Bool) -> Void
    @State private var copiedDebugSessionID: ComputerUseDebugSessionID?

    init(
        coordinator: ComputerUseCoordinator,
        modelSettings: ComputerUseModelSettingsController,
        onPageActiveChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.modelSettings = modelSettings
        self.onPageActiveChange = onPageActiveChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            composer
        }
        .background(MainWindowPalette.windowBackground)
        .onAppear {
            onPageActiveChange(true)
        }
        .onDisappear {
            onPageActiveChange(false)
        }
        .task {
            await coordinator.refreshPermissions()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Computer Use")
                .font(AppTypography.pageTitle)
            Spacer(minLength: 12)
            if let debugSessionID = coordinator.debugSessionID {
                Button {
                    copy(debugSessionID)
                } label: {
                    Label(
                        copiedDebugSessionID == debugSessionID ? "Copied" : "Copy debug ID",
                        systemImage: copiedDebugSessionID == debugSessionID
                            ? "checkmark"
                            : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderless)
                .help("Copy debug session ID \(debugSessionID.rawValue)")
                .accessibilityLabel("Copy debug session ID")
                .accessibilityIdentifier("computer-use-copy-debug-session-id")
            }
            Button {
                coordinator.startNewConversation()
            } label: {
                Label("New conversation", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .disabled(coordinator.isRunning || coordinator.conversation.isEmpty)
            .accessibilityIdentifier("computer-use-new-conversation")
        }
        .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
        .padding(.vertical, 16)
    }

    private func copy(_ debugSessionID: ComputerUseDebugSessionID) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(debugSessionID.rawValue, forType: .string) else {
            return
        }
        copiedDebugSessionID = debugSessionID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard copiedDebugSessionID == debugSessionID else { return }
            copiedDebugSessionID = nil
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if coordinator.conversation.isEmpty && !coordinator.isRunning {
                        ComputerUseEmptyConversation()
                    }

                    ForEach(coordinator.conversation) { message in
                        ComputerUseChatMessageRow(message: message)
                            .id(message.id)
                    }

                    if coordinator.isRunning {
                        ComputerUseWorkingRow()
                            .id(ComputerUseScrollTarget.working)
                    }

                    ComputerUseSettingsDisclosure(
                        coordinator: coordinator,
                        modelSettings: modelSettings
                    )
                    .padding(.top, 8)
                }
                .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
                .padding(.vertical, 28)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: coordinator.conversation.count) { _, _ in
                scrollToLatest(using: proxy)
            }
            .onChange(of: coordinator.isRunning) { _, _ in
                scrollToLatest(using: proxy)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let readinessMessage {
                Text(readinessMessage)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $coordinator.draft)
                    .font(AppTypography.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 38, maxHeight: 96)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .disabled(coordinator.isRunning)
                    .accessibilityLabel("Computer Use task")
                    .accessibilityHint("Press Return to send. Hold Shift and press Return for a new line.")
                    .accessibilityIdentifier("computer-use-composer")
                    .onKeyPress(.return, phases: .down) { keyPress in
                        guard !keyPress.modifiers.contains(.shift) else {
                            return .ignored
                        }
                        coordinator.submit()
                        return .handled
                    }

                Button(action: coordinator.isRunning ? coordinator.stop : coordinator.submit) {
                    Image(systemName: coordinator.isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(
                                composerButtonEnabled
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.35)
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!composerButtonEnabled)
                .help(coordinator.isRunning ? "Stop" : "Send")
                .accessibilityLabel(coordinator.isRunning ? "Stop" : "Send")
                .accessibilityIdentifier(
                    coordinator.isRunning ? "computer-use-stop" : "computer-use-send"
                )
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

    private var composerButtonEnabled: Bool {
        coordinator.isRunning || coordinator.canSubmit
    }

    private var readinessMessage: String? {
        if coordinator.isVoiceTaskPending {
            return "Voice task captured. Computer Use is preparing."
        }
        if !coordinator.isModelConfigured {
            return "Configure a model below to start."
        }
        if !coordinator.permissionSnapshot.canControlComputer {
            return "Grant the required permissions below to start."
        }
        if case .failed = coordinator.phase {
            return coordinator.errorMessage
        }
        return nil
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            if coordinator.isRunning {
                proxy.scrollTo(ComputerUseScrollTarget.working, anchor: .bottom)
            } else if let message = coordinator.conversation.last {
                proxy.scrollTo(message.id, anchor: .bottom)
            }
        }
    }
}

enum ComputerUseScrollTarget {
    static let working = "computer-use-working"
}
