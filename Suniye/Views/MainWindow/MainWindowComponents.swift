import AppKit
import SwiftUI

private extension NSAppearance {
    var usesDarkMainWindowPalette: Bool {
        bestMatch(from: [
            .darkAqua,
            .aqua,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastAqua
        ]).map { $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua } ?? false
    }

    /// True when the user has asked for increased contrast. Hairlines tuned for
    /// the default appearance disappear entirely at that setting.
    var usesIncreasedContrast: Bool {
        switch bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
        case .some(.accessibilityHighContrastAqua), .some(.accessibilityHighContrastDarkAqua):
            return true
        default:
            return false
        }
    }
}

private enum MainWindowNSPalette {
    static let baseSurface = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? .windowBackgroundColor
            : NSColor(calibratedWhite: 0.978, alpha: 1)
    })

    /// Cards sit on a near-opaque pane, so they are opaque too: the old
    /// high-alpha fill was tuned to let vibrancy through, and against a solid
    /// pane it composited to within a hair of the background and vanished.
    static let elevatedSurface = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor(calibratedWhite: 0.20, alpha: 1)
            : NSColor.white
    })

    /// Fields and editors. Darker than the pane where a card is lighter, so an
    /// input reads as recessed and a card as lifted.
    static let inputSurface = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor(calibratedWhite: 0.11, alpha: 1)
            : NSColor(calibratedWhite: 0.945, alpha: 1)
    })

    static let divider = NSColor(name: nil, dynamicProvider: { appearance in
        let alpha = appearance.usesIncreasedContrast ? 0.34 : 0.08
        return appearance.usesDarkMainWindowPalette
            ? NSColor.white.withAlphaComponent(alpha)
            : NSColor.black.withAlphaComponent(appearance.usesIncreasedContrast ? 0.32 : 0.06)
    })

    static let stroke = NSColor(name: nil, dynamicProvider: { appearance in
        let alpha = appearance.usesIncreasedContrast ? 0.38 : 0.1
        return appearance.usesDarkMainWindowPalette
            ? NSColor.white.withAlphaComponent(alpha)
            : NSColor.black.withAlphaComponent(appearance.usesIncreasedContrast ? 0.36 : 0.07)
    })

    static let selection = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.05)
    })
}

enum MainWindowPalette {
    static let windowBackgroundNSColor = MainWindowNSPalette.baseSurface
    static let windowBackground = Color(nsColor: MainWindowNSPalette.baseSurface)
    static let sidebarTitle = Color.primary.opacity(0.85)
    static let divider = Color(nsColor: MainWindowNSPalette.divider)
    /// Card surface. Solid, deliberately: the window's panes are already
    /// behind-window vibrancy, and stacking a translucent card on translucent
    /// chrome collapses legibility ("never stack a light translucent surface on
    /// another"). The pane is the glass; the card is the one opaque tier above it.
    static let cardBackground = Color(nsColor: MainWindowNSPalette.elevatedSurface)
    static let editorBackground = Color(nsColor: MainWindowNSPalette.inputSurface)
    static let cardStroke = Color(nsColor: MainWindowNSPalette.stroke)
    static let selectedFill = Color(nsColor: MainWindowNSPalette.selection)
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.76)
    static let destructive = Color.red.opacity(0.78)
}

enum AppTypography {
    // Semantic text styles so the UI follows the user's system text size; at the
    // default size these match the previous fixed points exactly (title2 17,
    // headline 13 semibold, body 13, callout 12, subheadline 11, caption 10).
    static let appTitle = Font.title2.weight(.semibold)
    static let sidebarIcon = Font.body
    static let sidebarLabel = Font.body
    static let sidebarLabelSelected = Font.body.weight(.medium)
    static let pageTitle = Font.title2.weight(.semibold)
    /// One rung below `pageTitle`, so a card heading cannot be mistaken for the
    /// page heading when both are on screen.
    static let cardTitle = Font.title3.weight(.semibold)
    /// Settings rows in the flattened pages: one step up from body, because with
    /// the cards gone the type carries the hierarchy.
    static let rowTitle = Font.callout
    /// Group heading — sentence case at body weight, not an uppercase mono label.
    static let groupHeading = Font.body.weight(.semibold)
    /// The Transcripts headline reads as a sentence, so it stays regular weight
    /// and leans on size alone.
    static let transcriptsHeadline = Font.system(.largeTitle, design: .default, weight: .regular)
    /// The newest transcript. Body size, same as the rows: the card already reads
    /// as featured through its surface and its untruncated text, so oversized
    /// type only made it shout.
    static let featuredTranscript = Font.body
    static let sectionHeading = Font.headline
    static let body = Font.body
    static let bodyMedium = Font.body.weight(.medium)
    static let subheadline = Font.subheadline
    static let subheadlineSemibold = Font.subheadline.weight(.semibold)
    static let caption = Font.caption
    static let callout = Font.callout
    static let calloutMedium = Font.callout.weight(.medium)
    static let codeCaption = Font.system(.caption, design: .monospaced, weight: .medium)
    static let codeBody = Font.system(.body, design: .monospaced)
    static let codeBodyMedium = Font.system(.body, design: .monospaced, weight: .medium)
    static let codeCalloutSemibold = Font.system(.callout, design: .monospaced, weight: .semibold)
    // Semantic, so the first screen a user meets still honours their text size.
    static let onboardingTitle = Font.title.weight(.semibold)
    static let metricValue = Font.system(.title, design: .rounded, weight: .semibold).monospacedDigit()
    static let emptyIcon = Font.system(size: 34, weight: .light)
}

enum AppMetrics {
    /// How opaque the detail pane's scrim is. 1 would kill the material
    /// entirely; this leaves just enough for the pane to still read as glass.
    static let detailPaneOpacity: Double = 0.9

    static let onboardingBrandIconSize: CGFloat = 64
    static let sidebarWidth: CGFloat = 208
    static let sidebarBrandTop: CGFloat = 24
    static let sidebarBrandHorizontal: CGFloat = 24
    static let sidebarBrandBottom: CGFloat = 24
    static let sidebarPaddingHorizontal: CGFloat = 14
    static let sidebarRowSpacing: CGFloat = 2
    static let sidebarRowHorizontalPadding: CGFloat = 12
    static let sidebarRowHeight: CGFloat = 32
    static let sidebarRowCornerRadius: CGFloat = 8
    /// The footer sits in its own block rather than reading as one more
    /// navigation row, so it is given more room than the rows above it.
    static let sidebarFooterRowHeight: CGFloat = 36
    static let sidebarFooterPadding: CGFloat = 18
    static let detailSpacing: CGFloat = 20
    static let detailPaddingHorizontal: CGFloat = 28
    static let detailPaddingTop: CGFloat = 24
    static let detailPaddingBottom: CGFloat = 24
    static let cardPadding: CGFloat = 12
    static let cardCornerRadius: CGFloat = 10
    static let metricPanelCornerRadius: CGFloat = 12
    static let cardSectionSpacing: CGFloat = 12
    static let listRowVerticalPadding: CGFloat = 10
    static let attentionPadding: CGFloat = 12
    static let attentionCornerRadius: CGFloat = 10
    static let attentionIconTopPadding: CGFloat = 1
    static let emptyStateSpacing: CGFloat = 14
    static let emptyStateMinHeight: CGFloat = 280
    static let emptyStateMaxWidth: CGFloat = 420
    static let disclosureContentTopPadding: CGFloat = 14
    static let disclosureContentSpacing: CGFloat = 14
    static let toggleDetailVerticalPadding: CGFloat = 10
    static let iconButtonSize: CGFloat = 24
}

struct SidebarNavigationRow: View {
    let section: MainWindowSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(AppTypography.sidebarIcon)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.primary : MainWindowPalette.secondaryText)
                Text(section.title)
                    .font(isSelected ? AppTypography.sidebarLabelSelected : AppTypography.sidebarLabel)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppMetrics.sidebarRowHorizontalPadding)
            .padding(.vertical, 6)
            .frame(minHeight: AppMetrics.sidebarRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.sidebarRowCornerRadius, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
        // Every system sidebar highlights under the pointer; this one did not.
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    /// A flat card surface: fill, an optional state tint over it, and a hairline.
    /// `tint` composites on top of `fill` rather than replacing it, so hover,
    /// selection and copy states read as a wash over the card's own colour.
    func flatSurface(
        in shape: some InsettableShape,
        fill: Color = MainWindowPalette.cardBackground,
        stroke: Color = MainWindowPalette.cardStroke,
        tint: Color? = nil
    ) -> some View {
        background {
            shape.fill(fill)
                .overlay(shape.fill(tint ?? .clear))
        }
        .overlay(shape.strokeBorder(stroke, lineWidth: 1))
    }
}

/// Press feedback for the window's custom buttons. `.plain` gives none at all,
/// so a click reads as dead until its side effect lands.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.snappy(duration: 0.1), value: configuration.isPressed)
    }
}

private extension SidebarNavigationRow {
    var rowFill: Color {
        if isSelected {
            return MainWindowPalette.selectedFill
        }
        return isHovered ? MainWindowPalette.selectedFill.opacity(0.5) : .clear
    }
}

struct DetailScrollContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: AppMetrics.detailSpacing) {
                content
            }
            .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
            .padding(.top, AppMetrics.detailPaddingTop)
            .padding(.bottom, AppMetrics.detailPaddingBottom)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .subtleEnclosingScroller()
        }
    }
}

struct NativePopupPicker<Item: Hashable>: NSViewRepresentable {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let isEnabled: (Item) -> Bool

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        isEnabled: @escaping (Item) -> Bool = { _ in true }
    ) {
        self.items = items
        _selection = selection
        self.title = title
        self.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionDidChange(_:))
        return button
    }

    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        context.coordinator.items = items

        let titles = items.map(title)
        let needsReload = nsView.itemTitles != titles

        if needsReload {
            nsView.removeAllItems()
            nsView.addItems(withTitles: titles)
        }

        for (index, item) in items.enumerated() {
            nsView.item(at: index)?.isEnabled = isEnabled(item)
        }

        if let selectedIndex = items.firstIndex(of: selection), nsView.indexOfSelectedItem != selectedIndex {
            nsView.selectItem(at: selectedIndex)
        }
    }

    final class Coordinator: NSObject {
        @Binding var selection: Item
        var items: [Item] = []

        init(selection: Binding<Item>) {
            _selection = selection
        }

        @objc func selectionDidChange(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard items.indices.contains(index) else {
                return
            }
            selection = items[index]
        }
    }
}

struct DetailPageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.pageTitle)
            .foregroundStyle(Color.primary)
    }
}

struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.sectionHeading)
            .foregroundStyle(Color.primary)
    }
}

struct SurfaceCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = AppMetrics.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .flatSurface(
            in: RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
        )
    }
}

struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(MainWindowPalette.divider)
            .frame(height: 1)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = MainWindowPalette.secondaryText
    var trailingIcon: String?
    var trailingIconColor: Color = .green

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTypography.body)
            Spacer(minLength: 12)
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .foregroundStyle(trailingIconColor)
            }
            Text(value)
                .font(AppTypography.body)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActionIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var tint: Color = MainWindowPalette.secondaryText
    /// Colour once the pointer is on this specific icon. Lets a row reveal its
    /// actions quietly and only commit to emphasis (red for a delete) when the
    /// pointer is actually on the thing that would fire.
    var hoverTint: Color?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppTypography.bodyMedium)
                .frame(width: AppMetrics.iconButtonSize, height: AppMetrics.iconButtonSize)
                .foregroundStyle(isHovered ? (hoverTint ?? tint) : tint)
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(IconButtonStyle(isHovered: isHovered))
        .contentShape(Circle())
        .accessibilityLabel(Text(accessibilityLabel))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Hover is the resting state; press stacks a deeper fill and a dip on top of it.
private struct IconButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle().fill(fill(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.1), value: configuration.isPressed)
            // Press was animated but hover was not, so the fill popped in hard.
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed {
            return MainWindowPalette.selectedFill.opacity(0.9)
        }
        return isHovered ? MainWindowPalette.selectedFill : .clear
    }
}

struct StatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(AppTypography.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

struct ModelTagBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.caption)
            .foregroundStyle(MainWindowPalette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(MainWindowPalette.selectedFill)
            )
    }
}

struct InlineStatusBanner: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(tint)

                Text(title)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(tint)
            }

            Text(detail)
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                .fill(MainWindowPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

struct AttentionTile: View {
    let item: AttentionItem
    let action: () -> Void
    let onFixAction: (AttentionItemFixAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                        .font(AppTypography.body)
                        .foregroundStyle(item.severity == .error ? Color.red : Color.orange)
                        .padding(.top, AppMetrics.attentionIconTopPadding)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(AppTypography.subheadlineSemibold)
                            .foregroundStyle(Color.primary)
                        Text(item.detail)
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if let fixAction = item.fixAction {
                Button(fixAction.title) {
                    onFixAction(fixAction)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(AppMetrics.attentionPadding)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.attentionCornerRadius, style: .continuous)
                .fill(MainWindowPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.attentionCornerRadius, style: .continuous)
                .stroke(item.severity == .error ? Color.red.opacity(0.16) : Color.orange.opacity(0.16), lineWidth: 1)
        )
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: AppMetrics.emptyStateSpacing) {
            Image(systemName: icon)
                .font(AppTypography.emptyIcon)
                .foregroundStyle(Color.secondary.opacity(0.72))
            Text(title)
                .font(AppTypography.pageTitle)
            Text(detail)
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: AppMetrics.emptyStateMaxWidth)
        }
        .frame(maxWidth: .infinity, minHeight: AppMetrics.emptyStateMinHeight)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(AppTypography.body)
                Spacer(minLength: 12)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(disabled)
            }
            if let detail {
                CardDivider()
                    .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)
                Text(detail)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PermissionActionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(AppTypography.body)
                        Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isGranted ? .green : .orange)
                    }

                    Text(detail)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(.bordered)
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct SecondaryDisclosureCard<Content: View>: View {
    let title: String
    @State private var isExpanded = false
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        SurfaceCard {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: AppMetrics.disclosureContentSpacing) {
                    content
                }
                .padding(.top, AppMetrics.disclosureContentTopPadding)
            } label: {
                Text(title)
                    .font(AppTypography.subheadlineSemibold)
            }
            .disclosureGroupStyle(.automatic)
        }
    }
}

extension Date {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var relativeTimestamp: String {
        Date.relativeFormatter.localizedString(for: self, relativeTo: .now)
    }
}

extension TimeInterval {
    var shortSecondsString: String {
        if self >= 60 {
            return compactDurationString
        }
        return String(format: "%.1fs", self)
    }

    /// Compact h/m/s. Without the hours branch a lifetime total rendered as
    /// "347m"; past an hour the seconds stop being interesting, so they are dropped.
    var compactDurationString: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        if minutes == 0 {
            return "\(seconds)s"
        }
        return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, position) in arrange(in: bounds.width, subviews: subviews).positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> ArrangeResult {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return ArrangeResult(
            size: CGSize(width: maxX, height: y + rowHeight),
            positions: positions
        )
    }
}

extension Int {
    /// Compact count in the user's locale. The hand-rolled version fell through
    /// to `ByteCountFormatter` past 9,999, so a 10,000-word total rendered as
    /// "10 KB" and a million words as "1 MB".
    var abbreviatedString: String {
        formatted(.number.notation(.compactName))
    }
}


/// Microphone picker in the sidebar's footer. The input device is the one
/// setting that decides whether dictation works at all, so it earns a permanent
/// place rather than living three clicks deep in General.
struct SidebarInputDeviceRow: View {
    @Bindable var appState: AppState

    @State private var isHovered = false

    var body: some View {
        Menu {
            Button {
                appState.selectedInputDeviceID = nil
            } label: {
                Label("System Default", systemImage: appState.selectedInputDeviceID == nil ? "checkmark" : "")
            }

            if !appState.availableInputDevices.isEmpty {
                Divider()
            }

            ForEach(appState.availableInputDevices) { device in
                Button {
                    appState.selectedInputDeviceID = device.id
                } label: {
                    Text(device.isAvailable ? device.name : "\(device.name) — Unavailable")
                }
                .disabled(!device.isAvailable)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: hasProblem ? "exclamationmark.triangle.fill" : "mic")
                    .font(AppTypography.subheadline)
                    .frame(width: 20)
                    .foregroundStyle(hasProblem ? Color.orange : MainWindowPalette.secondaryText)

                // The device name gives up space first: a long name must not
                // push the chevron off the edge and hide that this is a picker.
                // A footer control, not a destination: it sits a step below the
                // navigation rows above it.
                Text(appState.selectedInputDeviceName)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

            }
            .padding(.horizontal, AppMetrics.sidebarRowHorizontalPadding)
            .padding(.vertical, 7)
            .frame(minHeight: AppMetrics.sidebarFooterRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.sidebarRowCornerRadius, style: .continuous)
                    .fill(isHovered ? MainWindowPalette.selectedFill : .clear)
            )
            .contentShape(Rectangle())
        }
        // AppKit draws the popup indicator itself; a hand-rolled chevron got
        // squeezed off the edge by long device names.
        .menuStyle(.borderlessButton)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(appState.effectiveInputDeviceStatusText)
    }

    private var hasProblem: Bool {
        appState.audioRouteSnapshot == nil
    }
}
