import AppKit
import SwiftUI

/// The sidebar while Settings is open: a row back, the search field and the
/// panes. A query replaces the panes with its results.
struct SettingsSidebar: View {
    @Bindable var appState: AppState
    let panes: [SettingsPane]
    @Binding var selectedPane: SettingsPane
    @Binding var query: String
    /// Set when something asks for the search field, such as ⌘K.
    @Binding var focusPending: Bool
    /// Where the back row returns to, for its spoken name.
    let backTitle: String
    /// The recording dot, which the hidden Meetings row would otherwise carry.
    let backAccessory: SidebarRowAccessory?
    let onBack: () -> Void
    let onOpen: (SettingsRowID) -> Void

    @State private var selectedRow: SettingsRowID?
    /// ⌘K and ⌘F select the old query, so typing starts a new search.
    @State private var focusTrigger = 0
    @FocusState private var isPaneListFocused: Bool

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
                focusTrigger: focusTrigger,
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
                focusTrigger += 1
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: query) { _, _ in
            selectedRow = nil
        }
        .task(id: focusPending) {
            guard focusPending else {
                return
            }
            focusTrigger += 1
            focusPending = false
        }
    }

    /// One keyboard stop: ↑ and ↓ move between panes, as in any Mac sidebar.
    private var paneList: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sidebarRowSpacing) {
            ForEach(panes) { pane in
                SidebarNavigationRow(
                    title: pane.title,
                    icon: pane.icon,
                    isSelected: pane == selectedPane,
                    showsFocus: isPaneListFocused && pane == selectedPane,
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
                stepPane(by: -1)
            case .down:
                stepPane(by: 1)
            default:
                break
            }
        }
    }

    private func stepPane(by step: Int) {
        guard let index = panes.firstIndex(of: selectedPane) else {
            return
        }
        selectedPane = panes[min(max(index + step, 0), panes.count - 1)]
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
        let selection = Self.selection(selectedRow, in: results)

        Text(numbers: Self.countLine(results.count))
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

    /// The arrow keys move through the results and the pane follows, as a
    /// list selection does. A Magic Format result waits for Return: opening it
    /// leaves Settings, which would end the search.
    private func moveSelection(by step: Int) {
        guard !query.isEmpty else {
            stepPane(by: step)
            return
        }
        let results = results
        guard let current = Self.selection(selectedRow, in: results),
              let index = results.firstIndex(of: current) else {
            return
        }
        let row = results[min(max(index + step, 0), results.count - 1)]
        selectedRow = row
        AccessibilityNotification.Announcement("\(row.title), \(row.place.title)").post()
        if row.place != .magicFormat {
            open(row)
        }
    }

    private func openSelection() {
        if let row = Self.selection(selectedRow, in: results) {
            open(row)
        }
    }

    private func open(_ row: SettingsRowID) {
        onOpen(row.searchTarget(in: appState))
    }

    /// The chosen result while it is still listed, otherwise the first one: a
    /// new query or a change in what the app shows can remove the chosen row.
    private static func selection(_ chosen: SettingsRowID?, in results: [SettingsRowID]) -> SettingsRowID? {
        if let chosen, results.contains(chosen) {
            return chosen
        }
        return results.first
    }

    private static func countLine(_ count: Int) -> String {
        switch count {
        case 0:
            return "No results"
        case 1:
            return "1 result"
        default:
            return "\(count) results"
        }
    }
}

/// A search result: the row title with the matched words in bold, and where
/// the row is. The arrow keys move the selection without animation.
private struct SettingsResultRow: View {
    let row: SettingsRowID
    let query: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

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
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.sidebarRowCornerRadius, style: .continuous)
                    .fill(fill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("\(row.title), \(row.place.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected {
            return MainWindowPalette.selectedFill
        }
        return isHovered ? MainWindowPalette.selectedFill.opacity(0.5) : .clear
    }
}

extension SettingsPane {
    /// The dot or status at the end of the pane's sidebar row.
    @MainActor
    func sidebarAccessory(_ appState: AppState) -> SidebarRowAccessory? {
        switch self {
        case .permissions:
            return .attention
        case .microphone:
            return MicrophonePane.inputWarning(appState) == nil ? nil : .attention
        case .shortcuts:
            let hasProblem = appState.hotkeyValidationMessage != nil || ShortcutsPane.globeNotice(appState) != nil
            return hasProblem ? .attention : nil
        case .speechModel:
            if appState.phase == .downloadingModel {
                return .status("\(Int(appState.downloadProgress * 100))%")
            }
            let loadFailed = appState.phase == .error && appState.lastFailedASRModelID == appState.selectedASRModelID
            return appState.phase == .needsModel || loadFailed ? .attention : nil
        case .general:
            return GeneralSettingsPane.launchAtLoginNotice(appState) == nil ? nil : .attention
        case .indicator, .meetings:
            return nil
        }
    }
}

/// The search field, drawn like a sidebar row: the same height, corner and
/// grid, so the magnifier sits in the icon column and the text starts on the
/// labels' edge.
private struct SettingsSearchBox: View {
    @Binding var text: String
    let focusTrigger: Int
    let onMove: (Int) -> Void
    let onSubmit: () -> Void

    @State private var isFocused = false
    @State private var isHovered = false
    /// A click on the magnifier or the padding focuses the field too.
    @State private var clicks = 0

    var body: some View {
        HStack(spacing: AppMetrics.sidebarIconSpacing) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.sidebarIcon)
                .frame(width: AppMetrics.sidebarIconColumn)
                .foregroundStyle(MainWindowPalette.secondaryText)

            SettingsSearchTextField(
                text: $text,
                isFocused: $isFocused,
                focusTrigger: focusTrigger,
                clickTrigger: clicks,
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
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.sidebarRowCornerRadius, style: .continuous)
                .fill(isFocused || isHovered ? MainWindowPalette.selectedFill : MainWindowPalette.selectedFill.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.sidebarRowCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isFocused ? 0.55 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { clicks &+= 1 }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// A borderless AppKit text field. Its delegate sees the arrow keys, Return and
/// Esc, which a SwiftUI text field keeps for the text cursor.
private struct SettingsSearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    /// A new value moves the keyboard focus to the field and selects the
    /// query, so typing starts a new search (⌘K, ⌘F).
    let focusTrigger: Int
    /// A new value moves the keyboard focus to the field with the caret after
    /// the query (a click on the box).
    let clickTrigger: Int
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
            coordinator?.parent.isFocused = true
        }
        return field
    }

    func updateNSView(_ field: FocusOnArrivalTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if focusTrigger != context.coordinator.handledFocusTrigger {
            context.coordinator.handledFocusTrigger = focusTrigger
            field.takeFocusWhenInWindow(selectingAll: true)
        }
        if clickTrigger != context.coordinator.handledClickTrigger {
            context.coordinator.handledClickTrigger = clickTrigger
            field.takeFocusWhenInWindow(selectingAll: false)
        }
    }

    static func dismantleNSView(_ field: FocusOnArrivalTextField, coordinator: Coordinator) {
        field.delegate = nil
        field.onFocus = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsSearchTextField
        /// Start at the current requests, so a rebuilt field does not take the
        /// focus for a request that an earlier field already handled.
        var handledFocusTrigger: Int
        var handledClickTrigger: Int

        init(parent: SettingsSearchTextField) {
            self.parent = parent
            handledFocusTrigger = parent.focusTrigger
            handledClickTrigger = parent.clickTrigger
        }

        /// Every edit, as it happens, so a SwiftUI update never writes old
        /// text back over what was typed.
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
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
