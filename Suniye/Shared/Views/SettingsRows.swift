import SwiftUI

/// A settings page: the title (and an optional line under it) pinned at the
/// top, then sections of rows in cards. The column has one left edge for the
/// title and the cards, 28 pt from the pane like the other pages, and stops
/// growing at a readable width. A search result or a link scrolls to its row.
struct SettingsForm<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    var subtitleTint: Color = MainWindowPalette.settingsSecondaryText
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    @Environment(\.settingsHighlight) private var highlight

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: AppMetrics.settingsSectionSpacing) {
                    content
                }
                .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
                .padding(.top, 20)
                .padding(.bottom, AppMetrics.detailPaddingBottom + 8)
                .modifier(SettingsColumn())
                .subtleEnclosingScroller()
            }
            .modifier(SettingsFormHeaderBar(header: header))
            // A result opens from the keyboard as often as from a click, so the
            // row is brought into view at once rather than scrolled to.
            .task(id: highlight) {
                guard let highlight else {
                    return
                }
                proxy.scrollTo(highlight.row, anchor: .center)
            }
        }
    }

    /// The accessory (Magic Format's switch) sits on the title's line, not on
    /// the middle of the title and its status line.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // As tall as the sidebar's app icon row, so the title and the
                // app name share a center line.
                Text(title)
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(MainWindowPalette.settingsText)
                    .lineLimit(1)
                    .frame(minHeight: AppMetrics.sidebarBrandIcon)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    // Two lines at most: the bar does not scroll, so an unbounded
                    // line count at a narrow width would set the window's
                    // minimum height.
                    Text(numbers: subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(subtitleTint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
        .padding(.top, AppMetrics.detailPaddingTop)
        .padding(.bottom, 4)
        .modifier(SettingsColumn())
    }
}

extension SettingsForm where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// The page column: full width up to the readable maximum, then centered, for
/// the title bar and the sections alike.
private struct SettingsColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: AppMetrics.settingsColumnMaxWidth + 2 * AppMetrics.detailPaddingHorizontal, alignment: .topLeading)
            .frame(maxWidth: .infinity)
    }
}

/// Pins the title above the scrolling sections. From macOS 26 the system blurs
/// the rows that scroll under it; before that the bar takes the pane color.
private struct SettingsFormHeaderBar<Header: View>: ViewModifier {
    let header: Header

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.safeAreaBar(edge: .top, spacing: 0) {
                header
            }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                header.background(MainWindowPalette.windowBackground)
            }
        }
    }
}

/// A group of rows: an optional heading, the rows in one card, and an optional
/// footer. The heading and the footer start where the row text starts.
struct SettingsSection<Content: View, Footer: View>: View {
    let header: String?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(_ header: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.header = header
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        let card = RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(AppTypography.settingsSectionTitle)
                    .foregroundStyle(MainWindowPalette.settingsText)
                    .padding(.horizontal, AppMetrics.settingsRowInset)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 0) {
                content
            }
            // Every row draws a hairline above itself; this moves the first
            // one outside the card, where the clip hides it.
            .padding(.top, -1)
            .frame(maxWidth: .infinity)
            .background(MainWindowPalette.settingsCard)
            .clipShape(card)
            .overlay(card.strokeBorder(MainWindowPalette.settingsCardBorder, lineWidth: 1))

            footer
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.settingsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppMetrics.settingsRowInset)
        }
    }
}

extension SettingsSection where Footer == EmptyView {
    init(_ header: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(header, content: content, footer: { EmptyView() })
    }
}

extension View {
    /// What every row in a card shares: the padding, the minimum height, the
    /// hairline above it, and the highlight and scroll anchor.
    func settingsRowChrome(_ anchor: SettingsRowID?) -> some View {
        self
            .padding(.horizontal, AppMetrics.settingsRowInset)
            .padding(.vertical, AppMetrics.settingsRowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: AppMetrics.settingsRowMinHeight, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(MainWindowPalette.settingsDivider)
                    .frame(height: 1)
                    .padding(.horizontal, AppMetrics.settingsRowInset)
            }
            .settingsRowAnchor(anchor)
    }
}

/// The row grid: title and hint on the leading side, the control on the
/// trailing side, aligned on the title's first line.
struct SettingsRowLayout<Control: View>: View {
    let title: String
    var info: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(numbers: title)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(MainWindowPalette.settingsText)
                if let info {
                    Text(numbers: info)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.settingsSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
                .layoutPriority(1)
        }
    }
}

/// Content that is not a title and a control, such as a demonstration or a
/// list of words, padded and divided like a row.
struct SettingsCustomRow<Content: View>: View {
    var anchor: SettingsRowID?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsRowChrome(anchor)
    }
}

/// Lays its content out at its ideal width, but never wider than `maxWidth`:
/// a menu that lists long names stays as narrow as its current choice allows.
struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else {
            return .zero
        }
        let ideal = content.sizeThatFits(.unspecified).width
        let width = min(ideal, maxWidth, proposal.width ?? .infinity)
        return content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// A row that opens something: the value it is set to, then a chevron, or an
/// arrow when it opens something outside this window (a website, Finder,
/// another window).
struct DisclosureSettingRow: View {
    let title: String
    var secondLine: String?
    let value: String
    var isEnabled = true
    var opensOutside = false
    var anchor: SettingsRowID?
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            SettingsRowLayout(title: title, info: secondLine) {
                trailing
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(MainWindowPalette.settingsSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280, alignment: .trailing)
            }
            .settingsRowChrome(anchor)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowButtonStyle())
        .disabled(!isEnabled || action == nil)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private extension DisclosureSettingRow {
    /// The value and the chevron are one line of text, so the chevron sits on
    /// the same baseline as the value and the title. Middle truncation keeps
    /// the chevron at the end.
    var trailing: Text {
        let chevron = Text(Image(systemName: opensOutside ? "arrow.up.forward" : "chevron.forward"))
            .font(AppTypography.caption.weight(.semibold))
        switch (value.isEmpty, isEnabled) {
        case (true, true):
            return chevron
        case (true, false):
            return Text(verbatim: "")
        case (false, true):
            return Text(numbers: value) + Text(verbatim: "  ") + chevron
        case (false, false):
            return Text(numbers: value)
        }
    }
}

/// A row that opens something shows the press at once, as a system list row
/// does, because the sheet, window or Finder it opens can take a moment. The
/// fill fades on release; there is no scale, rows do not move.
private struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(MainWindowPalette.selectedFill.opacity(configuration.isPressed ? 1 : 0))
            .animation(configuration.isPressed ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Hairline between rows outside a settings card, such as in sheets.
struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(MainWindowPalette.divider)
            .frame(height: 1)
    }
}

/// A row whose control is a switch.
struct ToggleSettingRow: View {
    let title: String
    var info: String?
    @Binding var isOn: Bool
    var isEnabled = true
    var anchor: SettingsRowID?

    var body: some View {
        SettingsRowLayout(title: title, info: info) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .settingsRowChrome(anchor)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A row that only reports a value: no chevron, because nothing opens.
struct ValueSettingRow: View {
    let title: String
    var info: String?
    let value: String
    var anchor: SettingsRowID?

    var body: some View {
        SettingsRowLayout(title: title, info: info) {
            Text(numbers: value)
                .font(AppTypography.rowTitle)
                .foregroundStyle(MainWindowPalette.settingsSecondaryText)
                .multilineTextAlignment(.trailing)
        }
        .settingsRowChrome(anchor)
    }
}

/// A row whose control is a menu or any small inline control.
struct ControlSettingRow<Control: View>: View {
    let title: String
    var info: String?
    var isEnabled = true
    var anchor: SettingsRowID?
    @ViewBuilder let control: Control

    var body: some View {
        SettingsRowLayout(title: title, info: info) {
            control
        }
        .settingsRowChrome(anchor)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A row that a search result or a link points at, for a moment after it opens.
/// Every opening has its own identity: opening the same row again scrolls to it
/// again, and only the newest opening may end the highlight.
struct SettingsHighlight: Equatable {
    let row: SettingsRowID
    let id = UUID()
}

extension EnvironmentValues {
    @Entry var settingsHighlight: SettingsHighlight? = nil
}

extension View {
    /// Makes a settings row a scroll target that lights up, edge to edge in its
    /// card, while it is the highlight.
    @ViewBuilder
    func settingsRowAnchor(_ row: SettingsRowID?) -> some View {
        if let row {
            modifier(SettingsRowHighlight(row: row))
        } else {
            self
        }
    }
}

private struct SettingsRowHighlight: ViewModifier {
    let row: SettingsRowID

    @Environment(\.settingsHighlight) private var highlight

    /// The tint is on when the row appears, so the eye lands on it with no
    /// wait, and it fades out over half a second. A fade needs no reduced
    /// motion variant.
    func body(content: Content) -> some View {
        let isLit = highlight?.row == row
        content
            .background(Color.accentColor.opacity(isLit ? 0.12 : 0))
            .animation(isLit ? nil : .easeOut(duration: 0.5), value: isLit)
            .id(row)
    }
}

extension View {
    /// A control that a search result points at, such as a page's main switch:
    /// a capsule lights up around it.
    func settingsControlAnchor(_ row: SettingsRowID) -> some View {
        modifier(SettingsControlHighlight(row: row))
    }
}

private struct SettingsControlHighlight: ViewModifier {
    let row: SettingsRowID

    @Environment(\.settingsHighlight) private var highlight

    func body(content: Content) -> some View {
        let isLit = highlight?.row == row
        content
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(isLit ? 0.18 : 0))
                    .padding(-5)
            )
            .animation(isLit ? nil : .easeOut(duration: 0.5), value: isLit)
            .id(row)
    }
}

/// Motion for content that inserts into or leaves a settings list: banners,
/// warnings, rows that only exist in one state. These push everything below
/// them, so the reflow is what actually needs bridging — the transition is
/// deliberately just opacity, letting the container animate the layout.
enum SettingsMotion {
    static func curve(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    /// Opacity only, so it needs no reduced-motion variant: a cross-fade is
    /// already the gentle form.
    static let notice: AnyTransition = .opacity

    /// The page-level banner sits above everything and shoves the whole page
    /// down, so it also comes from the edge it pushes from.
    static func banner(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }
}
