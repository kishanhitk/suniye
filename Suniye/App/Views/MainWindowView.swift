import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var selection: MainWindowSection
    /// Kept while Settings is closed, so Settings reopens on the pane the user
    /// left.
    @State private var settingsPane: SettingsPane
    /// Where the back row of the Settings sidebar returns to.
    @State private var sectionBeforeSettings: MainWindowSection = .dashboard
    @State private var settingsQuery = ""
    @State private var searchFocusPending = false
    @State private var highlight: SettingsHighlight?
    private let appIdentity = AppIdentity.current

    init(appState: AppState) {
        _appState = Bindable(appState)
        let destination = MainWindowDestination.initial(arguments: CommandLine.arguments)
        _selection = State(initialValue: destination.section)
        _settingsPane = State(initialValue: destination.pane ?? Self.paneToOpen(appState: appState, last: .microphone))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(MainWindowPalette.divider)
                .frame(width: 1)
                // Full height, like the panes on both sides of it.
                .ignoresSafeArea()
            detail
                .background {
                    // The sidebar stays fully vibrant. Content needs to be read,
                    // so the detail pane keeps the blur only as a hint: a
                    // high-alpha scrim over it lets a little of the desktop
                    // through without the text competing with a wallpaper.
                    BehindWindowBlur(material: .underWindowBackground)
                        .overlay(MainWindowPalette.windowBackground.opacity(AppMetrics.detailPaneOpacity))
                        .ignoresSafeArea()
                }
        }
        .onAppear {
            logRenderedSection()
        }
        .onChange(of: selection) { _, _ in
            logRenderedSection()
        }
        .onChange(of: settingsPane) { _, _ in
            logRenderedSection()
        }
        .onChange(of: appState.requestedDestination, initial: true) { _, destination in
            guard let destination else { return }
            open(destination)
            appState.requestedDestination = nil
        }
        // The Permissions pane leaves the list once every grant is in.
        .onChange(of: permissionsMissing, initial: true) { _, _ in
            settingsPane = listedPane(settingsPane)
        }
        .task(id: highlight) {
            guard let opened = highlight else {
                return
            }
            try? await Task.sleep(for: .seconds(1.6))
            if highlight == opened {
                highlight = nil
            }
        }
        .subtleScrollers()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The icon is centered on the rows' icon column and the name starts
            // on their text edge.
            HStack(spacing: AppMetrics.sidebarBrandSpacing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: AppMetrics.sidebarBrandIcon, height: AppMetrics.sidebarBrandIcon)
                Text(appIdentity.displayName)
                    .font(AppTypography.appTitle)
                    .foregroundStyle(MainWindowPalette.sidebarTitle)
            }
            .padding(.top, AppMetrics.sidebarBrandTop)
            .padding(.horizontal, AppMetrics.sidebarBrandHorizontal)
            .padding(.bottom, AppMetrics.sidebarBrandBottom)

            Group {
                if selection == .settings {
                    SettingsSidebar(
                        appState: appState,
                        panes: SettingsPane.listed(permissionsMissing: permissionsMissing),
                        selectedPane: $settingsPane,
                        query: $settingsQuery,
                        focusPending: $searchFocusPending,
                        backTitle: sectionBeforeSettings.title,
                        backAccessory: accessory(for: .meetings),
                        onBack: { open(.section(sectionBeforeSettings)) },
                        onOpen: { open(.row($0)) }
                    )
                } else {
                    VStack(alignment: .leading, spacing: AppMetrics.sidebarRowSpacing) {
                        ForEach(MainWindowSection.allCases, id: \.self) { section in
                            SidebarNavigationRow(
                                title: section.title,
                                icon: section.icon,
                                isSelected: selection == section,
                                accessory: accessory(for: section)
                            ) {
                                open(.section(section))
                            }
                            .accessibilityIdentifier(section.accessibilityIdentifier)
                        }
                    }
                }
            }
            .padding(.horizontal, AppMetrics.sidebarPaddingHorizontal)
            // All the free height goes to this block, so a long list of search
            // results scrolls in the whole sidebar, not in half of it.
            .frame(maxHeight: .infinity, alignment: .top)

            // Full bleed: it separates the footer from the pane, so it runs the
            // sidebar's whole width rather than lining up with the rows.
            Rectangle()
                .fill(MainWindowPalette.divider)
                .frame(height: 1)
                .padding(.bottom, AppMetrics.sidebarFooterPadding)

            SidebarInputDeviceRow(appState: appState)
                .padding(.horizontal, AppMetrics.sidebarPaddingHorizontal)
                .padding(.bottom, AppMetrics.sidebarFooterPadding)
        }
        .frame(width: AppMetrics.sidebarWidth)
        .background { BehindWindowBlur(material: .sidebar).ignoresSafeArea() }
    }

    private var detail: some View {
        Group {
            switch selection {
            case .dashboard:
                TranscriptsPage(appState: appState) { open($0) }
            case .meetings:
                MeetingsSection(meetings: appState.meetings, appState: appState)
            case .style:
                StylePage(appState: appState)
            case .settings:
                SettingsPaneView(appState: appState, pane: settingsPane)
            }
        }
        .environment(\.settingsHighlight, highlight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Deliberately below the perception threshold: switching sections is a
        // frequent act, and anything you can consciously see here is a tax. A
        // cross-fade (not a slide) is also the Reduce Motion-friendly form.
        .transition(.opacity)
        .animation(.easeOut(duration: 0.12), value: selection)
        .animation(.easeOut(duration: 0.12), value: settingsPane)
    }

    private var permissionsMissing: Bool {
        Self.permissionsMissing(appState)
    }

    private func listedPane(_ pane: SettingsPane) -> SettingsPane {
        Self.listedPane(pane, permissionsMissing: permissionsMissing)
    }

    private func accessory(for section: MainWindowSection) -> SidebarRowAccessory? {
        switch section {
        case .meetings:
            return appState.meetings.live.map { .recording($0.isPaused ? .paused : .recording) }
        case .settings:
            let panes = SettingsPane.listed(permissionsMissing: permissionsMissing)
            return panes.contains { $0.sidebarAccessory(appState) == .attention } ? .attention : nil
        case .style:
            // A download shows its progress; a setup that stops Magic Format
            // from running gets the dot.
            if let progress = appState.localGemmaInstallProgress {
                return .status("\(Int(progress * 100))%")
            }
            switch appState.magicFormatSetupState {
            case .needsAPIKey, .needsServiceSetup:
                return .attention
            case .ready, .off:
                return nil
            }
        case .dashboard:
            return nil
        }
    }

    private func open(_ destination: MainWindowDestination) {
        if destination.section == .settings {
            if let pane = destination.pane {
                settingsPane = listedPane(pane)
            } else if selection != .settings {
                settingsPane = Self.paneToOpen(appState: appState, last: settingsPane)
            }
            if selection != .settings {
                sectionBeforeSettings = selection
            }
            if destination.focusesSearch {
                searchFocusPending = true
            }
        } else if destination.row == nil {
            // A Magic Format result leaves Settings but keeps the query, so ⌘K
            // brings the same results back.
            settingsQuery = ""
        }
        selection = destination.section
        highlight = destination.row.map { SettingsHighlight(row: $0) }
    }

    /// Permissions while a grant is missing, so the blocker is the first thing
    /// Settings shows; otherwise the pane the user had open.
    private static func paneToOpen(appState: AppState, last: SettingsPane) -> SettingsPane {
        let missing = permissionsMissing(appState)
        return missing ? .permissions : listedPane(last, permissionsMissing: missing)
    }

    private static func listedPane(_ pane: SettingsPane, permissionsMissing: Bool) -> SettingsPane {
        pane == .permissions && !permissionsMissing ? .microphone : pane
    }

    private static func permissionsMissing(_ appState: AppState) -> Bool {
        !appState.hasMicPermission || !appState.hasAccessibilityPermission
    }

    private func logRenderedSection() {
        let pane = selection == .settings ? " pane=\(settingsPane.rawValue)" : ""
        AppLogger.shared.log(.info, "main window section rendered section=\(selection.rawValue)\(pane)")
    }
}
