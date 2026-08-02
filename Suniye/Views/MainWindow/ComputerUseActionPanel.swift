import SwiftUI

struct ComputerUseActionPanel: View {
    @Bindable var coordinator: ComputerUseCoordinator

    var body: some View {
        if coordinator.observation != nil {
            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Controlled actions")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Every action requires approval. Longer approval scopes appear only when policy allows them.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)

                        HStack(spacing: 10) {
                            Button {
                                guard let point = clickPoint else {
                                    return
                                }
                                coordinator.requestAction(.click(point: point))
                            } label: {
                                Label("Click center", systemImage: "cursorarrow.click")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                coordinator.requestAction(
                                    .keyPress(
                                        key: .named(.returnKey),
                                        modifiers: ComputerUseKeyModifiers()
                                    )
                                )
                            } label: {
                                Label("Press Return", systemImage: "return")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                coordinator.requestAction(.scroll(horizontal: 0, vertical: -400))
                            } label: {
                                Label("Scroll down", systemImage: "arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(!coordinator.canRequestAction)

                        HStack(spacing: 10) {
                            TextField("Text to enter", text: $coordinator.actionText)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                coordinator.requestAction(.typeText(coordinator.actionText))
                            } label: {
                                Label("Request text entry", systemImage: "character.cursor.ibeam")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!coordinator.canRequestAction || coordinator.actionText.isEmpty)
                        }

                        if !semanticCandidates.isEmpty {
                            CardDivider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Semantic Accessibility actions")
                                    .font(AppTypography.subheadlineSemibold)

                                ForEach(Array(semanticCandidates.enumerated()), id: \.offset) { _, candidate in
                                    Button {
                                        coordinator.requestAction(
                                            .semantic(
                                                elementIndex: candidate.elementIndex,
                                                action: candidate.action
                                            )
                                        )
                                    } label: {
                                        HStack {
                                            Text(candidate.title)
                                            Spacer(minLength: 8)
                                            Image(systemName: "arrow.right")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!coordinator.canRequestAction)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var clickPoint: ComputerUsePoint? {
        guard let observation = coordinator.observation else {
            return nil
        }
        let bounds = observation.target.window.bounds.cgRect
        return ComputerUsePoint(x: bounds.midX, y: bounds.midY)
    }

    private var semanticCandidates: [SemanticCandidate] {
        guard let observation = coordinator.observation else {
            return []
        }

        return observation.accessibility.elements.flatMap { element in
            ComputerUseSemanticAction.allCases.compactMap { action in
                guard element.actions.contains(action.rawValue) else {
                    return nil
                }
                return SemanticCandidate(
                    elementIndex: element.index,
                    action: action,
                    title: "\(element.index) · \(element.role ?? "element") · \(action.rawValue)"
                )
            }
        }
        .prefix(8)
        .map { $0 }
    }
}

private struct SemanticCandidate {
    let elementIndex: Int
    let action: ComputerUseSemanticAction
    let title: String
}

struct ComputerUseApprovalCard: View {
    let request: ComputerUseApprovalRequest
    let allow: (ComputerUseApprovalScope) -> Void
    let deny: () -> Void
    let stop: () -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Text("Approval required")
                        .font(AppTypography.bodyMedium)
                    Spacer(minLength: 8)
                    StatusPill(title: request.risk.title, tint: .orange)
                }

                Text(request.reason)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)

                VStack(alignment: .leading, spacing: 5) {
                    approvalValue(title: "Application", value: request.target.application.displayName)
                    approvalValue(title: "Bundle ID", value: request.target.application.bundleIdentifier)
                    approvalValue(
                        title: "Window",
                        value: request.target.window.title ?? "Untitled"
                    )
                    approvalValue(title: "Action", value: request.action.summary)
                    if let textPreview = request.textPreview {
                        approvalValue(title: "Text", value: textPreview)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(ComputerUseApprovalScope.allCases.filter(request.allowedScopes.contains), id: \.self) { scope in
                        Button(scope.title) {
                            allow(scope)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Deny", action: deny)
                        .buttonStyle(.bordered)
                    Button("Stop Session", action: stop)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func approvalValue(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(AppTypography.codeCaption)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
        }
    }
}
