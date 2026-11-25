import AppKit
import SwiftUI

/// The sidebar while Settings is open: a row back, the search box and the
/// panes. A query replaces the panes with its results.
struct SettingsSidebar: View {
    @Bindable var appState: AppState
    let panes: [SettingsPane]
    @Binding var selectedPane: SettingsPane
    @Binding var query: String
    /// Set when something asks for the search box, such as ⌘K.
    @Binding var focusPending: Bool
    /// Where the back row returns to, for its spoken name.
    let backTitle: String
    /// The recording dot, which the hidden Meetings row would otherwise carry.
    let backAccessory: SidebarRowAccessory?
    let onBack: () -> Void
    let onOpen: (SettingsRowID) -> Void

    @State private var selectedRow: SettingsRowID?
    @State private var focusRequest: SearchFocusRequest?
    @FocusState private var isPaneListFocused: Bool
    @State private var isUsingKeyboard = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sidebarRowSpacing) {
            SidebarNavigationRow(
                title: MainWindowSection.settings.title,
                icon: "chevron.backward",
                isSelected: false,
                accessory: backAccessory,
                action: onBack
            )
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityLabel("Back to \(backTitle)")
            .accessibilityInputLabels([Text("Back"), Text(MainWindowSection.settings.title)])

            SettingsSearchBox(
                text: $query,
                focusRequest: $focusRequest,
                onMove: moveSelection,
                onSubmit: openSelection
            )
            .padding(.vertical, 6)

            if query.isEmpty {
                paneList
            } else {
                resultList
            }
        }
        // Permissions leaves the list when the last grant arrives, usually
        // while the user is away in System Settings: the rows close the gap
        // instead of jumping.
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: panes)
        .background {
            // ⌘F finds in Settings as it does on Transcripts. A key
            // equivalent, so it works wherever the focus is in the window.
            Button("Find in Settings") {
                focusRequest = SearchFocusRequest(selectsAll: true)
            }
            .keyboardShortcut("f", modifiers: .command)
            .focusable(false)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .background(KeyboardUseMonitor(isUsingKeyboard: $isUsingKeyboard))
        .onChange(of: query) { _, _ in
            selectedRow = nil
        }
        .onChange(of: focusPending, initial: true) { _, pending in
            guard pending else {
                return
            }
            focusRequest = SearchFocusRequest(selectsAll: true)
            focusPending = false
        }
    }

    /// One keyboard stop: ↑ and ↓ move between panes, as in any Mac sidebar.
    /// A click also gives the list the focus, so the arrow keys work after
    /// it, but the focus edge waits for a key press.
    private var paneList: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sidebarRowSpacing) {
            ForEach(panes) { pane in
                SidebarNavigationRow(
                    title: pane.title,
                    icon: pane.icon,
                    isSelected: pane == selectedPane,
                    showsFocus: isPaneListFocused && isUsingKeyboard && pane == selectedPane,
                    accessory: pane.sidebarAccessory(appState)
                ) {
                    selectedPane = pane
                    isPaneListFocused = true
                }
                .accessibilityIdentifier("settings-pane-\(pane.rawValue)")
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isPaneListFocused)
        .onMoveCommand { direction in
            switch direction {
            case .up:
                selectedPane = selectedPane.moving(by: -1, in: panes)
            case .down:
                selectedPane = selectedPane.moving(by: 1, in: panes)
            default:
                break
            }
        }
    }

    private var results: [SettingsRowID] {
        SettingsSearch.results(
            for: query,
            in: SettingsRowID.allCases.filter { $0.isSearchable(in: appState) },
            info: { $0.currentInfo(in: appState) }
        )
    }

    @ViewBuilder
    private var resultList: some View {
        let results = results
        let selection = SettingsSearch.selection(selectedRow, in: results)

        Text(numbers: SettingsSearch.countLine(results.count))
            .font(AppTypography.caption)
            .foregroundStyle(MainWindowPalette.secondaryText)
            .padding(.leading, AppMetrics.sidebarTextInset)
            .padding(.top, 2)
            .padding(.bottom, 4)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.sidebarRowSpacing) {
                    ForEach(results, id: \.self) { row in
                        SettingsResultRow(row: row, query: query, isSelected: row == selection) {
                            selectedRow = row
                            open(row)
                        }
                        .id(row)
                    }
                }
            }
            .onChange(of: selectedRow) { _, row in
                if let row {
                    proxy.scrollTo(row)
                }
            }
        }
    }

    /// With a query the arrow keys move through the results and the pane
    /// follows, as a list selection does; without one they move between
    /// panes. A Magic Format result waits for Return: opening it leaves
    /// Settings, which would end the search.
    private func moveSelection(by step: Int) {
        guard !query.isEmpty else {
            selectedPane = selectedPane.moving(by: step, in: panes)
            return
        }
        guard let row = SettingsSearch.moving(selectedRow, by: step, in: results) else {
            return
        }
        selectedRow = row
        AccessibilityNotification.Announcement("\(row.title), \(row.place.title)").post()
        if row.place != .magicFormat {
            open(row)
        }
    }

    private func openSelection() {
        if let row = SettingsSearch.selection(selectedRow, in: results) {
            open(row)
        }
    }

    private func open(_ row: SettingsRowID) {
        onOpen(row.searchTarget(in: appState))
    }
}

/// A search result: the row title with the matched words in bold, and where
/// the row is. The arrow keys move the selection without animation.
private struct SettingsResultRow: View {
    let row: SettingsRowID
    let query: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: AppMetrics.sidebarIconSpacing) {
                Image(systemName: row.place.icon)
                    .font(AppTypography.sidebarIcon)
                    .frame(width: AppMetrics.sidebarIconColumn)
                    .foregroundStyle(isSelected ? Color.primary : MainWindowPalette.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsSearch.emphasized(row.title, query: query))
                        .font(AppTypography.sidebarLabel)
                        .foregroundStyle(Color.primary)
                    Text(row.place.title)
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
            }
            .padding(.horizontal, AppMetrics.sidebarRowHorizontalPadding)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sidebarRowBackground(isSelected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
        .accessibilityLabel("\(row.title), \(row.place.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A request for the keyboard focus in the search box. Each request has its
/// own identity, so a rebuilt field never handles one twice.
private struct SearchFocusRequest: Equatable {
    let id = UUID()
    /// ⌘K and ⌘F select the old query, so typing starts a new search; a click
    /// puts the caret after it.
    let selectsAll: Bool
}

/// The search box, drawn like a sidebar row: the same height, corner and
/// grid, so the magnifier sits in the icon column and the text starts on the
/// labels' edge.
private struct SettingsSearchBox: View {
    @Binding var text: String
    @Binding var focusRequest: SearchFocusRequest?
    let onMove: (Int) -> Void
    let onSubmit: () -> Void

    @State private var isFocused = false

    var body: some View {
        HStack(spacing: AppMetrics.sidebarIconSpacing) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.sidebarIcon)
                .frame(width: AppMetrics.sidebarIconColumn)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .allowsHitTesting(false)

            SettingsSearchTextField(
                text: $text,
                isFocused: $isFocused,
                focusRequest: focusRequest,
                onMove: onMove,
                onSubmit: onSubmit
            )

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.callout)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppMetrics.sidebarRowHorizontalPadding)
        .frame(height: AppMetrics.sidebarRowHeight)
        // A click on the magnifier or the padding focuses the field. A click on
        // the text reaches the field itself, which places the caret there.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    focusRequest = SearchFocusRequest(selectsAll: false)
                }
        }
        .sidebarRowBackground(isSelected: isFocused, showsFocus: isFocused, isRaised: true)
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// A borderless AppKit text field. Its delegate sees the arrow keys, Return and
/// Esc, which a SwiftUI text field keeps for the text cursor.
private struct SettingsSearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusRequest: SearchFocusRequest?
    let onMove: (Int) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> FocusOnArrivalTextField {
        let field = FocusOnArrivalTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(
            string: "Search settings",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
        )
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.onFocus = { [weak coordinator = context.coordinator] in
            coordinator?.setFocused(true)
        }
        return field
    }

    func updateNSView(_ field: FocusOnArrivalTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if let focusRequest, focusRequest.id != context.coordinator.handledRequestID {
            context.coordinator.handledRequestID = focusRequest.id
            field.takeFocusWhenInWindow(selectingAll: focusRequest.selectsAll)
        }
    }

    static func dismantleNSView(_ field: FocusOnArrivalTextField, coordinator: Coordinator) {
        field.delegate = nil
        field.onFocus = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsSearchTextField
        /// Starts at the current request, so a rebuilt field does not take the
        /// focus for a request that an earlier field already handled.
        var handledRequestID: UUID?

        init(parent: SettingsSearchTextField) {
            self.parent = parent
            handledRequestID = parent.focusRequest?.id
        }

        /// Every edit, as it happens, so a SwiftUI update never writes old
        /// text back over what was typed.
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            setFocused(false)
        }

        /// On the next turn of the main queue: the field takes the focus from
        /// `updateNSView`, and SwiftUI state must not change during an update.
        /// The queue keeps the order of focus and end of editing.
        func setFocused(_ focused: Bool) {
            DispatchQueue.main.async { [self] in
                parent.isFocused = focused
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // Esc clears the query; a second Esc leaves the field.
                if parent.text.isEmpty {
                    control.window?.makeFirstResponder(nil)
                } else {
                    parent.text = ""
                }
                return true
            default:
                return false
            }
        }
    }
}

/// Takes focus when asked, or as soon as it reaches a window: ⌘K on another
/// page asks before this field exists.
private final class FocusOnArrivalTextField: NSTextField {
    var onFocus: (() -> Void)?
    /// Set while a focus request waits for the field to reach a window: the
    /// value says whether to select the query.
    private var pendingFocus: Bool?

    func takeFocusWhenInWindow(selectingAll: Bool) {
        if window != nil {
            focus(selectingAll: selectingAll)
        } else {
            pendingFocus = selectingAll
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let selectingAll = pendingFocus, window != nil else {
            return
        }
        pendingFocus = nil
        focus(selectingAll: selectingAll)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onFocus?()
        }
        return became
    }

    /// AppKit selects all the text when the field takes the focus. A click
    /// keeps the caret after the text instead, so the next key adds to the
    /// query rather than replacing it.
    private func focus(selectingAll: Bool) {
        guard window?.makeFirstResponder(self) == true else {
            return
        }
        let length = (stringValue as NSString).length
        currentEditor()?.selectedRange = selectingAll
            ? NSRange(location: 0, length: length)
            : NSRange(location: length, length: 0)
    }
}
