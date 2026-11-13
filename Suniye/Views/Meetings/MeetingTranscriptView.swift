import AppKit
import SwiftUI

struct MeetingTranscriptLine: Equatable {
    let id: UUID
    let time: String
    /// "You" or "Them"; nil when the meeting had no call track.
    let speaker: String?
    let text: String
}

/// The notes that the user types, saved a moment after each edit and when
/// the editor goes away. Only an edit saves: notes that failed to load are
/// never written over.
struct MeetingNotesEditor: View {
    @Binding var text: String
    /// The notes on disk when the editor appears.
    let saved: String
    let save: (String) -> Void
    @State private var lastSaved: String?

    var body: some View {
        TextEditor(text: $text)
            .font(AppTypography.body)
            .scrollContentBackground(.hidden)
            .task(id: text) {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                saveIfEdited()
            }
            .onDisappear {
                saveIfEdited()
            }
    }

    private func saveIfEdited() {
        guard text != (lastSaved ?? saved) else { return }
        lastSaved = text
        save(text)
    }
}

/// The transcript as one read-only text view, so a selection can cross lines
/// and ⌘F opens the native find bar. While the meeting records, new lines
/// follow at the end; a "Latest" button shows when they arrive below the
/// visible part.
struct MeetingTranscriptView: View {
    let lines: [MeetingTranscriptLine]
    let followsLatest: Bool
    @State private var hasNewLinesBelow = false
    @State private var scrollToEnd = 0

    var body: some View {
        TranscriptTextView(
            lines: lines,
            followsLatest: followsLatest,
            scrollToEnd: scrollToEnd,
            hasNewLinesBelow: $hasNewLinesBelow
        )
        .overlay(alignment: .bottom) {
            if hasNewLinesBelow {
                Button {
                    scrollToEnd += 1
                } label: {
                    Label("Latest", systemImage: "arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clipShape(Capsule())
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: hasNewLinesBelow)
    }
}

private struct TranscriptTextView: NSViewRepresentable {
    let lines: [MeetingTranscriptLine]
    let followsLatest: Bool
    let scrollToEnd: Int
    @Binding var hasNewLinesBelow: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainerInset = NSSize(width: 0, height: 4)
        }
        context.coordinator.observe(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.hasNewLinesBelow = $hasNewLinesBelow
        let wasAtBottom = coordinator.isAtBottom(scrollView)
        let added = coordinator.render(lines, into: textView)
        if scrollToEnd != coordinator.scrollToEnd {
            coordinator.scrollToEnd = scrollToEnd
            textView.scrollToEndOfDocument(nil)
            hasNewLinesBelowLater(false)
        } else if added, followsLatest {
            if wasAtBottom {
                textView.scrollToEndOfDocument(nil)
            } else {
                hasNewLinesBelowLater(true)
            }
        }
    }

    /// SwiftUI state cannot change while it updates this view.
    private func hasNewLinesBelowLater(_ value: Bool) {
        DispatchQueue.main.async { hasNewLinesBelow = value }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hasNewLinesBelow: $hasNewLinesBelow)
    }

    @MainActor
    final class Coordinator: NSObject {
        var hasNewLinesBelow: Binding<Bool>
        var scrollToEnd = 0
        private var rendered: [UUID] = []

        init(hasNewLinesBelow: Binding<Bool>) {
            self.hasNewLinesBelow = hasNewLinesBelow
        }

        func observe(_ scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        @objc private func boundsChanged(_ notification: Notification) {
            guard let clip = notification.object as? NSClipView, let scrollView = clip.enclosingScrollView else { return }
            if isAtBottom(scrollView), hasNewLinesBelow.wrappedValue {
                hasNewLinesBelow.wrappedValue = false
            }
        }

        func isAtBottom(_ scrollView: NSScrollView) -> Bool {
            guard let document = scrollView.documentView else { return true }
            return scrollView.contentView.bounds.maxY >= document.bounds.maxY - 24
        }

        /// Appends the lines after the ones on screen when the old lines are
        /// unchanged; otherwise draws all of them again. True when lines were
        /// added.
        func render(_ lines: [MeetingTranscriptLine], into textView: NSTextView) -> Bool {
            let ids = lines.map(\.id)
            guard ids != rendered, let storage = textView.textStorage else { return false }
            if ids.starts(with: rendered) {
                storage.append(Self.text(for: lines.dropFirst(rendered.count)))
            } else {
                storage.setAttributedString(Self.text(for: lines[...]))
            }
            let added = ids.count > rendered.count
            rendered = ids
            return added
        }

        private static func text(for lines: ArraySlice<MeetingTranscriptLine>) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 64), NSTextTab(textAlignment: .left, location: 116)]
            paragraph.headIndent = 116
            paragraph.paragraphSpacing = 10
            let body = NSFont.preferredFont(forTextStyle: .body)
            let output = NSMutableAttributedString()
            for line in lines {
                output.append(NSAttributedString(string: line.time + "\t", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: body.pointSize, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                ]))
                output.append(NSAttributedString(string: (line.speaker ?? "") + "\t", attributes: [
                    .font: NSFont.systemFont(ofSize: body.pointSize, weight: .medium),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph,
                ]))
                output.append(NSAttributedString(string: line.text + "\n", attributes: [
                    .font: body,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph,
                ]))
            }
            return output
        }
    }
}
