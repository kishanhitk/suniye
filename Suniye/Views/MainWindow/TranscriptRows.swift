import AppKit
import SwiftUI

extension String {
    /// The transcript with every case- and diacritic-insensitive occurrence of
    /// `query` tinted, so a search result shows *why* it matched.
    func highlightingMatches(of query: String) -> AttributedString {
        var attributed = AttributedString(self)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return attributed
        }

        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let match = attributed[searchStart...].range(
                  of: needle,
                  options: [.caseInsensitive, .diacriticInsensitive]
              ) {
            attributed[match].backgroundColor = Color.accentColor.opacity(0.28)
            // Step past this match; a zero-width result would otherwise spin.
            guard match.upperBound > searchStart else {
                break
            }
            searchStart = match.upperBound
        }
        return attributed
    }
}

/// Icon of the app a dictation was inserted into. Falls back to a neutral swatch
/// for history written before the source app was recorded.
struct TranscriptAppIcon: View {
    let bundleID: String?
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let icon {
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

    private var icon: NSImage? {
        guard
            let bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}


/// The newest transcript, shown in full. It is the one the user is most likely
/// to want to reuse, so its text is not truncated and Copy is always visible.
struct FeaturedTranscriptCard: View {
    let result: RecentResult
    var isSelected = false
    var searchQuery = ""
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var isHovered = false

    private var cardTint: Color? {
        if didCopy {
            return Color.green.opacity(0.16)
        }
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        return isHovered ? Color.primary.opacity(0.06) : nil
    }

    var body: some View {
        Button(action: copy) {
            card
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.995))
        .accessibilityLabel("Copy transcript")
        .accessibilityHint("Copies this transcript")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.text.highlightingMatches(of: searchQuery))
                .font(AppTypography.featuredTranscript)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                TranscriptAppIcon(bundleID: result.appBundleID, size: 13)
                Text(result.metaLine)
                    .font(AppTypography.codeCaption)
                    .foregroundStyle(MainWindowPalette.secondaryText)

                Spacer(minLength: 12)

                // Clicking the card copies; the icon is still a button so it
                // answers the pointer. Same resting weight as the delete beside
                // it: full-strength
                // primary made copy read as the louder of the two. Still
                // monochrome, so it follows the system theme.
                ActionIconButton(
                    systemName: didCopy ? "checkmark" : "doc.on.doc",
                    accessibilityLabel: "Copy transcript",
                    tint: didCopy ? .green : MainWindowPalette.tertiaryText,
                    hoverTint: Color.primary,
                    action: copy
                )

                // Visible, not hidden behind hover: it was reserving space while
                // invisible, which reads as a dead gap and hides a real action.
                // Quiet grey until the pointer is on it, then red.
                ActionIconButton(
                    systemName: "trash",
                    accessibilityLabel: "Delete transcript",
                    tint: MainWindowPalette.tertiaryText,
                    hoverTint: MainWindowPalette.destructive,
                    action: onDelete
                )

            }
        }
        .padding(16)
        .flatSurface(
            in: RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous),
            tint: cardTint
        )
        .overlay {
            // Selection needs to read at a glance; the tint alone is too quiet.
            if isSelected {
                RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func copy() {
        onCopy()
        didCopy = true
        AccessibilityNotification.Announcement("Copied").post()
        Task {
            try? await Task.sleep(for: .seconds(1))
            didCopy = false
        }
    }
}

/// One line per transcript: when, where, and enough text to recognise it.
struct CompactTranscriptRow: View {
    let result: RecentResult
    var isSelected = false
    var searchQuery = ""
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var didCopy = false
    @FocusState private var focusedAction: RowAction?

    private enum RowAction: Hashable {
        case delete
    }

    private var showsActions: Bool {
        isHovered || isSelected || didCopy || focusedAction != nil
    }

    var body: some View {
        Button(action: copy) {
            row
        }
        // No scale on a list row — a jiggling row reads as a glitch; the opacity
        // dip and the fill are enough.
        .buttonStyle(PressableButtonStyle(pressedScale: 1))
        .accessibilityLabel(result.text)
        .accessibilityHint("Copies this transcript")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var row: some View {
        HStack(spacing: 12) {
            Text(result.createdAt.formatted(date: .omitted, time: .shortened))
                .font(AppTypography.codeCaption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)

            TranscriptAppIcon(bundleID: result.appBundleID)

            Text(result.text.highlightingMatches(of: searchQuery))
                .font(AppTypography.body)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Reserve the space so revealing the actions never reflows the row.
            HStack(spacing: 4) {
                // Clicking the row copies; the icon is still a button so it
                // responds to the pointer like the delete next to it.
                ActionIconButton(
                    systemName: didCopy ? "checkmark" : "doc.on.doc",
                    accessibilityLabel: "Copy transcript",
                    tint: didCopy ? .green : MainWindowPalette.tertiaryText,
                    hoverTint: Color.primary,
                    action: copy
                )

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
        onCopy()
        didCopy = true
        AccessibilityNotification.Announcement("Copied").post()
        Task {
            try? await Task.sleep(for: .seconds(1))
            didCopy = false
        }
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
