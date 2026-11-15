import AppKit
import MarkdownEngine
import SwiftUI

/// Markdown with a live preview: the marks hide, except on the line or the
/// span that holds the caret. The text goes in and comes back as Markdown.
/// Each change reports it, and the end of an edit reports it once more when
/// the edit changed the text. ⌘F opens the find bar.
struct MarkdownTextEditor: NSViewRepresentable {
    let markdown: String
    /// Keeps the undo history of one document apart from another.
    let documentID: String
    var isEditable = false
    var edited: (_ markdown: String, _ ended: Bool) -> Void = { _, _ in }

    func makeNSView(context: Context) -> Host {
        let model = Model(markdown: markdown, documentID: documentID)
        model.isEditable = isEditable
        return Host(model: model)
    }

    func updateNSView(_ host: Host, context: Context) {
        host.model.edited = edited
        host.model.isEditable = isEditable
        // The engine skips its own update while Writing Tools run.
        host.editorTextView?.isEditable = isEditable
        host.model.load(markdown)
    }

    /// The text that the editor shows and what the page last gave it.
    @MainActor
    @Observable
    final class Model {
        var text: String {
            didSet { textChanged() }
        }
        var isEditable = false
        var isFocused = false {
            didSet { focusChanged() }
        }
        @ObservationIgnored let documentID: String
        @ObservationIgnored var edited: (_ markdown: String, _ ended: Bool) -> Void = { _, _ in }
        /// The Markdown that the page gave last; an edit that comes back from
        /// the page is no new text.
        @ObservationIgnored private var source: String
        /// The user changed the text since the edit began.
        @ObservationIgnored private var changed = false
        @ObservationIgnored private var loading = false

        init(markdown: String, documentID: String) {
            text = markdown
            source = markdown
            self.documentID = documentID
        }

        func load(_ markdown: String) {
            guard markdown != source else { return }
            source = markdown
            guard markdown != text else { return }
            loading = true
            text = markdown
            loading = false
        }

        private func textChanged() {
            guard !loading, text != source else { return }
            source = text
            changed = true
            edited(text, false)
        }

        private func focusChanged() {
            guard !isFocused, changed else { return }
            changed = false
            edited(text, true)
        }
    }

    /// Holds the engine's view. The engine keeps its text view to itself, so
    /// the host finds it below itself to turn on the find bar, and to pass
    /// an undo on as a change: a TextKit 2 text view sends no change notice
    /// for an undo or a redo, so the engine would not see the undone text.
    /// The host also lays the text view out again when the text grows: the
    /// engine keeps a short text at the height of the view, and AppKit then
    /// does not grow the area that draws the text, so the last lines do not
    /// show.
    final class Host: NSView {
        let model: Model
        private let hosting: NSHostingView<EditorView>
        private weak var textView: NSTextView?
        private var undoObservers: [NSObjectProtocol] = []
        private var heightObservation: NSKeyValueObservation?

        init(model: Model) {
            self.model = model
            hosting = NSHostingView(rootView: EditorView(model: model))
            super.init(frame: .zero)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosting.topAnchor.constraint(equalTo: topAnchor),
                hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        deinit {
            undoObservers.forEach(NotificationCenter.default.removeObserver)
        }

        override func layout() {
            super.layout()
            attachIfNeeded()
        }

        /// The engine's text view, once it is in the view tree.
        var editorTextView: NSTextView? {
            attachIfNeeded()
            return textView
        }

        private func attachIfNeeded() {
            guard textView == nil, let found = Self.firstTextView(in: hosting) else { return }
            textView = found
            found.usesFindBar = true
            found.isIncrementalSearchingEnabled = true
            heightObservation = found.textLayoutManager?.observe(\.usageBoundsForTextContainer, options: .initial) { [weak found] _, _ in
                DispatchQueue.main.async { found?.needsLayout = true }
            }
            guard let undoManager = found.undoManager else { return }
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                // Queued behind the engine's own binding update for the text
                // before the undo, so the engine compares the undone text with it.
                undoObservers.append(NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: nil) { [weak found] _ in
                    DispatchQueue.main.async {
                        guard let found else { return }
                        NotificationCenter.default.post(name: NSText.didChangeNotification, object: found)
                    }
                })
            }
        }

        private static func firstTextView(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView {
                return textView
            }
            for subview in view.subviews {
                if let found = firstTextView(in: subview) {
                    return found
                }
            }
            return nil
        }
    }

    struct EditorView: View {
        @Bindable var model: Model

        var body: some View {
            NativeTextViewWrapper(
                text: $model.text,
                configuration: MarkdownTextEditor.configuration,
                fontSize: MarkdownTextEditor.bodyFont.pointSize,
                documentId: model.documentID,
                isEditable: model.isEditable,
                isFocused: $model.isFocused
            )
        }
    }

    static let bodyFont = NSFont.preferredFont(forTextStyle: .body)

    static var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.headings = HeadingStyle(
            fontMultipliers: [1.3, 1, 1, 1, 1, 1],
            topSpacingEm: [0.6, 0.6, 0.5, 0.5, 0.5, 0.5]
        )
        configuration.lists = ListStyle(autoClosePairsEnabled: false, indentPerLevel: 12, extraLineHeight: 0)
        configuration.paragraph = ParagraphStyle(spacingFactor: 0.5, lineHeightExtraSpacing: 0)
        configuration.textInsets = TextInsets(horizontal: 0, vertical: 4)
        configuration.overscroll = OverscrollPolicy(percent: 0, maxPoints: 0, minPoints: 0)
        configuration.theme = MarkdownEditorTheme(headingMarker: .tertiaryLabelColor, link: .controlAccentColor)
        return configuration
    }
}
