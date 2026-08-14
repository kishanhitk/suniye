import SwiftUI

struct ComputerUseEmptyConversation: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("What should I do on your Mac?")
                .font(AppTypography.pageTitle)
            Text("Ask Suniye to inspect or control a desktop app.")
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

struct ComputerUseChatMessageRow: View {
    let message: ComputerUseConversationMessage

    @ViewBuilder
    var body: some View {
        switch message.role {
        case .activity:
            if let activity = message.activity {
                ComputerUseActivityRow(activity: activity)
            }
        case .user, .assistant:
            conversationMessage
        }
    }

    private var conversationMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 72)
            } else {
                assistantMark
            }

            messageText
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
        .frame(
            maxWidth: .infinity,
            alignment: message.role == .user ? .trailing : .leading
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            message.role == .user
                ? "computer-use-user-message"
                : "computer-use-assistant-message"
        )
    }

    private var messageText: Text {
        if message.role == .assistant {
            Text(ComputerUseChatMarkdown.attributedString(from: message.text))
        } else {
            Text(verbatim: message.text)
        }
    }

    private var assistantMark: some View {
        Image(systemName: "cursorarrow.motionlines")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.accentColor))
    }
}

enum ComputerUseChatMarkdown {
    static func attributedString(from source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }
}

private struct ComputerUseActivityRow: View {
    let activity: ComputerUseActivity
    @State private var isOutputExpanded = false

    @ViewBuilder
    var body: some View {
        Group {
            if let output = activity.output {
                DisclosureGroup(isExpanded: $isOutputExpanded) {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .accessibilityIdentifier("computer-use-activity-output")
                } label: {
                    activityLabel
                }
                .tint(MainWindowPalette.secondaryText)
            } else {
                activityLabel
            }
        }
        .padding(.leading, 38)
        .accessibilityIdentifier("computer-use-activity")
    }

    private var activityLabel: some View {
        (Text(activity.toolName).fontWeight(.medium)
            + Text("  \(activity.arguments)"))
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(MainWindowPalette.secondaryText)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ComputerUseWorkingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            ComputerUseShimmeringText("Working")
                .font(AppTypography.bodyMedium)
            Spacer(minLength: 0)
        }
        .padding(.leading, 38)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working")
    }
}

private struct ComputerUseShimmeringText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.6) / 1.6
            Text(text)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            MainWindowPalette.secondaryText,
                            Color.primary,
                            MainWindowPalette.secondaryText
                        ],
                        startPoint: UnitPoint(x: phase - 0.6, y: 0.5),
                        endPoint: UnitPoint(x: phase + 0.6, y: 0.5)
                    )
                )
        }
    }
}
