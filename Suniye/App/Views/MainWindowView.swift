import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var navigation: MainWindowNavigation
    private let appIdentity = AppIdentity.current

    init(appState: AppState) {
        _appState = Bindable(appState)
        _navigation = State(initialValue: MainWindowNavigation(
            destination: MainWindowDestination.initial(arguments: CommandLine.arguments),
            permissionsMissing: !appState.hasMicPermission || !appState.hasAccessibilityPermission
        ))
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
        .onChange(of: navigation.selection) { _, _ in
            logRenderedSection()
        }
        .onChange(of: navigation.settingsPane) { _, _ in
            logRenderedSection()
        }
        .onChange(of: appState.requestedDestination, initial: true) { _, destination in
            guard let destination else { return }
            open(destination)
            appState.requestedDestination = nil
        }
        .onChange(of: permissionsMissing, initial: true) { _, missing in
            navigation.permissionsChanged(missing: missing)
        }
        .task(id: navigation.highlight) {
            guard let opened = navigation.highlight else {
                return
            }
            try? await Task.sleep(for: .seconds(1.6))
            navigation.endHighlight(opened)
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
                if navigation.selection == .settings {
                    SettingsSidebar(
                        appState: appState,
                        panes: SettingsPane.listed(permissionsMissing: permissionsMissing),
                        selectedPane: $navigation.settingsPane,
                        query: $navigation.settingsQuery,
                        focusPending: $navigation.searchFocusPending,
                        backTitle: navigation.sectionBeforeSettings.title,
                        backAccessory: MainWindowSection.meetings.sidebarAccessory(appState),
                        onBack: { open(.section(navigation.sectionBeforeSettings)) },
                        onOpen: { open(.row($0)) }
                    )
                } else {
                    VStack(alignment: .leading, spacing: AppMetrics.sidebarRowSpacing) {
                        ForEach(MainWindowSection.allCases, id: \.self) { section in
                            SidebarNavigationRow(
                                title: section.title,
                                icon: section.icon,
                                isSelected: navigation.selection == section,
                                accessory: section.sidebarAccessory(appState)
                            ) {
                                open(section == .settings ? .settings() : .section(section))
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
            switch navigation.selection {
            case .dashboard:
                TranscriptsPage(appState: appState) { open($0) }
            case .meetings:
                MeetingsSection(meetings: appState.meetings, appState: appState)
            case .style:
                StylePage(appState: appState)
            case .settings:
                SettingsPaneView(appState: appState, pane: navigation.settingsPane)
            }
        }
        .environment(\.settingsHighlight, navigation.highlight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Deliberately below the perception threshold: switching sections is a
        // frequent act, and anything you can consciously see here is a tax. A
        // cross-fade (not a slide) is also the Reduce Motion-friendly form.
        .transition(.opacity)
        .animation(.easeOut(duration: 0.12), value: navigation.selection)
        .animation(.easeOut(duration: 0.12), value: navigation.settingsPane)
    }

    private var permissionsMissing: Bool {
        !appState.hasMicPermission || !appState.hasAccessibilityPermission
    }

    private func open(_ destination: MainWindowDestination) {
        navigation.open(destination, permissionsMissing: permissionsMissing)
    }

    private func logRenderedSection() {
        let pane = navigation.selection == .settings ? " pane=\(navigation.settingsPane.rawValue)" : ""
        AppLogger.shared.log(.info, "main window section rendered section=\(navigation.selection.rawValue)\(pane)")
    }
}
