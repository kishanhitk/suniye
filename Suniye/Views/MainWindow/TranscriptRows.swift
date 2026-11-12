import AppKit
import SwiftUI


/// Icon of the app a dictation was inserted into. Falls back to a neutral swatch
/// for history written before the source app was recorded.
struct TranscriptAppIcon: View {
    let bundleID: String?
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let icon = bundleID.flatMap(AppIconCache.shared.icon(for:)) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                // A grey box shouts "missing image". A faint dot holds the
                // column's rhythm without pretending to be an icon — most
                // transcripts predate the app ever being recorded.
                Circle()
                    .fill(MainWindowPalette.tertiaryText.opacity(0.28))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

}



/// The newest transcript, shown in full. It is the one the user is most likely
/// to want to reuse, so its text is not truncated and Copy is always visible.
struct CompactTranscriptRow: View {
    let result: RecentResult
    var isSelected = false
    var searchQuery = ""
    let onCopy: () -> Bool
    let onCopyOriginal: (String) -> Bool
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isShowingOriginal = false

    /// Plain Text when there is nothing to highlight: building an
    /// AttributedString for every row on every evaluation is wasted work in
    /// the common case of no search.
    private var highlightedText: Text {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Text(result.text)
            : Text(result.text.highlightingMatches(of: searchQuery))
    }
    @State private var didCopy = false
    @FocusState private var focusedAction: RowAction?

    private enum RowAction: Hashable {
        case original
        case copy
        case delete
    }

    /// The popover counts too: the pointer leaves the row to reach it, and
    /// the icon it points at must not fade out under its arrow.
    private var showsActions: Bool {
        isHovered || isSelected || didCopy || isShowingOriginal || focusedAction != nil
    }

    var body: some View {
        // A tap gesture, not a Button: the row contains its own Copy and Delete
        // buttons, and a Button wrapping other Buttons swallows their clicks —
        // pressing the trash copied the transcript and never deleted it. The
        // gesture only fires for clicks that no child control handled, and
        // the visuals (fill, hover) are unchanged.
        row
            .contentShape(Rectangle())
            .onTapGesture(perform: copy)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(result.text)
            .accessibilityHint("Copies this transcript")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: "Copy", copy)
            .accessibilityActions {
                if let rawText = result.rawText {
                    Button("Copy original") {
                        copyOriginal(rawText)
                    }
                }
            }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Text(result.createdAt.formatted(date: .omitted, time: .shortened))
                .font(AppTypography.codeCaption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)

            TranscriptAppIcon(bundleID: result.appBundleID)

            highlightedText
                .font(AppTypography.body)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Reserve the space so revealing the actions never reflows the row.
            HStack(spacing: 4) {
                if let rawText = result.rawText {
                    ActionIconButton(
                        systemName: "quote.bubble",
                        accessibilityLabel: "Show original",
                        tint: isShowingOriginal ? Color.primary : MainWindowPalette.tertiaryText,
                        hoverTint: Color.primary,
                        action: { isShowingOriginal.toggle() }
                    )
                    .focused($focusedAction, equals: .original)
                    .help("Show original")
                    .popover(isPresented: $isShowingOriginal, arrowEdge: .bottom) {
                        OriginalTranscriptPopover(text: rawText) {
                            onCopyOriginal(rawText)
                        }
                    }
                }

                // Clicking the row copies; the icon is still a button so it
                // responds to the pointer like the delete next to it.
                // Focus is tracked here too, not just on delete: keyboard
                // users could otherwise land on a control the row keeps at
                // opacity zero.
                ActionIconButton(
                    systemName: didCopy ? "checkmark" : "doc.on.doc",
                    accessibilityLabel: "Copy transcript",
                    tint: didCopy ? .green : MainWindowPalette.tertiaryText,
                    hoverTint: Color.primary,
                    action: copy
                )
                .focused($focusedAction, equals: .copy)

                ActionIconButton(
                    systemName: "trash",
                    accessibilityLabel: "Delete transcript",
                    tint: MainWindowPalette.tertiaryText,
                    hoverTint: MainWindowPalette.destructive,
                    action: onDelete
                )
                .focused($focusedAction, equals: .delete)
            }
            .opacity(showsActions ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: showsActions)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowFill)
                .animation(.easeOut(duration: 0.12), value: didCopy)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .help(result.text)
    }

    private func copy() {
        // No checkmark and no announcement unless the pasteboard took it:
        // clearContents has already run, so a failed write leaves an empty
        // clipboard and a confirmation would be a lie.
        guard onCopy() else {
            return
        }
        didCopy = true
        AccessibilityNotification.Announcement("Copied").post()
        Task {
            try? await Task.sleep(for: .seconds(1))
            didCopy = false
        }
    }

    private func copyOriginal(_ rawText: String) {
        guard onCopyOriginal(rawText) else {
            return
        }
        AccessibilityNotification.Announcement("Copied original").post()
    }
}

/// What the user said before Magic Format changed it, readable in full and
/// selectable, since the row can only show one line of the final text.
private struct OriginalTranscriptPopover: View {
    let text: String
    let onCopy: () -> Bool

    @State private var didCopy = false
    @State private var copyCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Original")
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.tertiaryText)

            ScrollView {
                Text(text)
                    .font(AppTypography.body)
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicatorsFlash(onAppear: true)
            // A popover sizes to its content, and a bare ScrollView always
            // asks for the cap: a five-word original got a 240 pt box.
            .frame(maxHeight: 240)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                // Only the glyph confirms the copy: a "Copied" title is wider
                // and would move the button under the pointer.
                Button(action: copy) {
                    Label("Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        // Keyed on the copy count, so a second copy restarts the 1 s
        // checkmark instead of the first copy's timer cutting it short.
        .task(id: copyCount) {
            guard didCopy else {
                return
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            didCopy = false
        }
    }

    private func copy() {
        guard onCopy() else {
            return
        }
        didCopy = true
        copyCount += 1
        AccessibilityNotification.Announcement("Copied original").post()
    }
}

private extension CompactTranscriptRow {
    var rowFill: Color {
        if didCopy {
            return Color.green.opacity(0.14)
        }
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        return isHovered ? MainWindowPalette.selectedFill.opacity(0.5) : .clear
    }
}

extension RecentResult {
    /// "14:06 · Slack · 24 words · 10.0s", dropping any part we do not know.
    var metaLine: String {
        var parts = [createdAt.formatted(date: .omitted, time: .shortened)]
        if let appName {
            parts.append(appName)
        }
        parts.append("\(wordCount) words")
        parts.append(durationSeconds.shortSecondsString)
        return parts.joined(separator: " · ")
    }

    var appName: String? {
        guard
            let appBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID)
        else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
