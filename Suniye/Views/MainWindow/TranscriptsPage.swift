import SwiftUI

/// Dashboard and History were two views of the same thing — the dashboard's
/// "Recent" list was just a shorter history. This is the merged page: the stats
/// read as one sentence at the top, and everything below is the transcripts
/// themselves, grouped by day and searchable.
struct TranscriptsPage: View {
    @Bindable var appState: AppState
    let onNavigate: (MainWindowSection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isListFocused: Bool

    private var visibleResults: [RecentResult] {
        TranscriptBrowser.filter(appState.recentResults, searchText: searchText)
    }

    private var groups: [TranscriptDayGroup] {
        TranscriptBrowser.group(visibleResults)
    }

    var body: some View {
        DetailScrollContainer {
            attentionSection

            TranscriptsHeaderView(
                stats: appState.dictationStats,
                timeSaved: appState.timeSavedSeconds,
                wordsPerMinute: appState.averageWordsPerMinute,
                streakDays: appState.currentStreakDays,
                days: appState.dailyWordCounts(days: 14)
            )

            TranscriptSearchBar(
                searchText: $searchText,
                isSearchFocused: $isSearchFocused
            )

            transcripts
        }
        // Clicking anywhere that is not itself selectable drops the selection and
        // any field focus, the way clicking off a selection works everywhere else.
        // Rows and controls handle their own taps, so this only ever sees the
        // clicks nothing else claimed.
        .contentShape(Rectangle())
        .onTapGesture {
            clearSelection()
        }
        .onKeyPress(keys: ["f", "c"]) { press in
            handleCommandKey(press)
        }
        .onKeyPress(.escape) {
            guard !searchText.isEmpty || selectedID != nil || isSearchFocused else {
                return .ignored
            }
            searchText = ""
            clearSelection()
            return .handled
        }
        .onChange(of: searchText) { _, _ in selectedID = nil }
    }

    // MARK: - Sections

    @ViewBuilder
    private var attentionSection: some View {
        if !appState.attentionItems.isEmpty {
            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                ForEach(appState.attentionItems) { item in
                    AttentionTile(item: item) {
                        onNavigate(item.recommendedSection)
                    } onFixAction: { action in
                        appState.handleAttentionFixAction(action)
                    }
                    .transition(cardTransition)
                }
            }
        }

        if appState.shouldShowMagicFormatNudge {
            MagicFormatNudgeCard(
                onSetUp: { onNavigate(appState.openMagicFormatSetupFromNudge()) },
                onDismiss: { appState.dismissMagicFormatNudge() }
            )
            .transition(cardTransition)
            .onAppear {
                appState.magicFormatNudgeDidShow()
            }
        }
    }

    private var transcripts: some View {
        emptyStateAwareContent
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22),
                value: appState.recentResults.isEmpty
            )
    }

    @ViewBuilder
    private var emptyStateAwareContent: some View {
        if appState.recentResults.isEmpty {
            EmptyStateCard(
                icon: "quote.opening",
                title: "No Transcripts Yet",
                detail: "Hold \(appState.hotkeyConfiguration.displayString) in any app to dictate — everything you say shows up here."
            )
            .transition(SettingsMotion.notice)
        } else if visibleResults.isEmpty {
            EmptyStateCard(
                icon: "magnifyingglass",
                title: "No Matches",
                detail: "No transcripts match this search."
            )
        } else {
            ScrollViewReader { proxy in
                // Must stay lazy: history is unbounded and these rows are
                // variable height, so an eager stack lays out every stored
                // transcript on every update.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.results) { result in
                                row(for: result)
                                    .id(result.id)
                            }
                        } header: {
                            dayHeader(for: group)
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($isListFocused)
                .onMoveCommand { direction in
                    move(direction, proxy: proxy)
                }
                .onKeyPress(.delete) {
                    guard let selected = selectedResult else {
                        return .ignored
                    }
                    deleteAndAdvance(selected)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let selected = selectedResult else {
                        return .ignored
                    }
                    appState.copyRecentResult(selected)
                    AccessibilityNotification.Announcement("Copied").post()
                    return .handled
                }
            }
        }
    }

    @ViewBuilder
    private func row(for result: RecentResult) -> some View {
        // The newest transcript is the one most likely to be reused, so it is
        // shown in full rather than truncated to a line.
        if result.id == visibleResults.first?.id {
            FeaturedTranscriptCard(
                result: result,
                isSelected: selectedID == result.id,
                searchQuery: searchText,
                onCopy: {
                    select(result)
                    appState.copyRecentResult(result)
                },
                onDelete: { deleteAndAdvance(result) }
            )
            .padding(.bottom, 6)
        } else {
            CompactTranscriptRow(
                result: result,
                isSelected: selectedID == result.id,
                searchQuery: searchText,
                onCopy: {
                    select(result)
                    appState.copyRecentResult(result)
                },
                onDelete: { deleteAndAdvance(result) }
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(MainWindowPalette.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func dayHeader(for group: TranscriptDayGroup) -> some View {
        Text(TranscriptBrowser.dayTitle(for: group.date).uppercased())
            .font(AppTypography.caption)
            .tracking(0.8)
            .foregroundStyle(MainWindowPalette.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, group.id == groups.first?.id ? 0 : 18)
            .padding(.bottom, 8)
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    // MARK: - Selection and keyboard

    private var selectedResult: RecentResult? {
        guard let selectedID else {
            return nil
        }
        return visibleResults.first { $0.id == selectedID }
    }

    private func select(_ result: RecentResult) {
        selectedID = result.id
        isSearchFocused = false
        isListFocused = true
    }

    private func clearSelection() {
        guard selectedID != nil || isSearchFocused || isListFocused else {
            return
        }
        selectedID = nil
        isSearchFocused = false
        isListFocused = false
    }

    /// Arrow keys walk the flattened, filtered list — day headers are labels, not
    /// stops, so navigation ignores them.
    private func move(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        let results = visibleResults
        guard !results.isEmpty else {
            return
        }

        let currentIndex = selectedID.flatMap { id in results.firstIndex { $0.id == id } }
        let nextIndex: Int

        switch direction {
        case .down:
            nextIndex = currentIndex.map { min($0 + 1, results.count - 1) } ?? 0
        case .up:
            nextIndex = currentIndex.map { max($0 - 1, 0) } ?? 0
        default:
            return
        }

        selectedID = results[nextIndex].id
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            proxy.scrollTo(results[nextIndex].id, anchor: .center)
        }
    }

    /// Keeps the selection on a real row after a delete, so repeated presses keep
    /// working instead of dropping focus.
    private func deleteAndAdvance(_ result: RecentResult) {
        let results = visibleResults
        let index = results.firstIndex { $0.id == result.id }
        appState.deleteRecentResult(result)

        guard let index else {
            selectedID = nil
            return
        }
        // The row below takes the deleted row's place; if there was none, fall
        // back to the row above.
        if index + 1 < results.count {
            selectedID = results[index + 1].id
        } else if index > 0 {
            selectedID = results[index - 1].id
        } else {
            selectedID = nil
        }
    }

    private func handleCommandKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command) else {
            return .ignored
        }
        switch press.key {
        case "f":
            isSearchFocused = true
            return .handled
        case "c":
            guard let selectedResult else {
                return .ignored
            }
            appState.copyRecentResult(selectedResult)
            AccessibilityNotification.Announcement("Copied").post()
            return .handled
        default:
            return .ignored
        }
    }
}

/// The stats as a sentence rather than a row of tiles: what you did, and what it
/// bought you, in the order you would say it out loud.
struct TranscriptsHeaderView: View {
    let stats: DictationStats
    let timeSaved: TimeInterval
    let wordsPerMinute: Int
    let streakDays: Int
    let days: [DailyWordCount]

    var body: some View {
        // Bottom-aligned so the sparkline's caption sits on the same line as the
        // words/wpm/streak summary rather than floating above it.
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                headline
                Text(subline)
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            Spacer(minLength: 12)

            if stats.lifetimeSessions > 0 {
                TranscriptsSparkline(days: days)
            }
        }
        .padding(.bottom, 4)
    }

    /// Two deliberate lines rather than one wrapping sentence: left to wrap on
    /// its own the headline broke mid-value ("32m" / "49s saved"), which reads as
    /// a mistake.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(stats.lifetimeSessions.formatted()) dictation\(stats.lifetimeSessions == 1 ? "" : "s")")

            (
                Text(timeSaved.compactDurationString).foregroundColor(.accentColor)
                    + Text(" saved")
            )
        }
        .font(AppTypography.transcriptsHeadline)
        .tracking(AppTypography.transcriptsHeadlineTracking)
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stats.lifetimeSessions) dictations, \(timeSaved.compactDurationString) saved versus typing")
    }

    private var subline: String {
        var parts = ["\(stats.lifetimeWords.formatted()) words"]
        if wordsPerMinute > 0 {
            parts.append("\(wordsPerMinute) wpm")
        }
        if streakDays > 0 {
            parts.append("\(streakDays)-day streak")
        }
        return parts.joined(separator: " · ")
    }
}

/// Search, left-aligned with the list it filters.
///
/// The three time windows that used to sit beside it are gone: the list is
/// already newest-first and grouped by day, so "Today" only truncated a list
/// whose top was already today. Search is the one axis that reaches something
/// scrolling cannot.
struct TranscriptSearchBar: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.tertiaryText)

                TextField("Search transcripts", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MainWindowPalette.tertiaryText)
                    }
                    .buttonStyle(PressableButtonStyle(pressedScale: 0.9))
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 260)
            .frame(minHeight: 30)
            .flatSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: MainWindowPalette.editorBackground,
                stroke: isSearchFocused ? Color.accentColor.opacity(0.55) : MainWindowPalette.cardStroke
            )

            Spacer(minLength: 12)
        }
        .animation(.easeOut(duration: 0.12), value: isSearchFocused)
    }
}
