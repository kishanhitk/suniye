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

    /// Increase Contrast raises the fill; at 5 to 8 percent the selected row
    /// is hard to find with that setting on.
    static let selection = NSColor(name: nil, dynamicProvider: { appearance in
        let strong = appearance.usesIncreasedContrast
        return appearance.usesDarkMainWindowPalette
            ? NSColor.white.withAlphaComponent(strong ? 0.22 : 0.08)
            : NSColor.black.withAlphaComponent(strong ? 0.16 : 0.05)
    })

    /// Warning text, also on an orange-tinted tag: dark brown on light, light
    /// orange on dark.
    static let warningText = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor(srgbRed: 1, green: 0.72, blue: 0.4, alpha: 1)
            : NSColor(srgbRed: 0.54, green: 0.29, blue: 0, alpha: 1)
    })

    // Settings: neutral grays with no tint, in the Vercel manner. Each text
    // color keeps at least 4.5:1 against the card it sits on (WCAG AA for
    // small text); the ratio is noted next to each value.

    /// White on the light pane; #262626, one step above the dark pane.
    static let settingsCard = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 1)
            : NSColor.white
    })

    static let settingsCardBorder = NSColor(name: nil, dynamicProvider: { appearance in
        let strong = appearance.usesIncreasedContrast
        return appearance.usesDarkMainWindowPalette
            ? NSColor.white.withAlphaComponent(strong ? 0.36 : 0.09)
            : NSColor.black.withAlphaComponent(strong ? 0.34 : 0.09)
    })

    static let settingsDivider = NSColor(name: nil, dynamicProvider: { appearance in
        let strong = appearance.usesIncreasedContrast
        return appearance.usesDarkMainWindowPalette
            ? NSColor.white.withAlphaComponent(strong ? 0.3 : 0.07)
            : NSColor.black.withAlphaComponent(strong ? 0.28 : 0.06)
    })

    /// #171717, 17.9:1 on white; #EDEDED, 12.9:1 on the dark card.
    static let settingsText = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor(srgbRed: 0.929, green: 0.929, blue: 0.929, alpha: 1)
            : NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1)
    })

    /// Hints and values: #666666, 5.7:1 on white; #A1A1A1, 5.9:1 on the dark
    /// card. The system secondary label is 4.0:1 on white. Increase Contrast
    /// moves them toward the primary text.
    static let settingsSecondaryText = NSColor(name: nil, dynamicProvider: { appearance in
        let value: CGFloat
        if appearance.usesDarkMainWindowPalette {
            value = appearance.usesIncreasedContrast ? 0.78 : 0.631
        } else {
            value = appearance.usesIncreasedContrast ? 0.28 : 0.4
        }
        return NSColor(srgbRed: value, green: value, blue: value, alpha: 1)
    })

    /// 5.4:1 on white, 5.2:1 on the dark card. The system red is 3.6:1 on white.
    static let errorText = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor(srgbRed: 1, green: 0.39, blue: 0.41, alpha: 1)
            : NSColor(srgbRed: 0.8, green: 0.16, blue: 0.18, alpha: 1)
    })

    /// 5.3:1 on white, 6.7:1 on the dark card. The system green is 2.2:1 on white.
    static let successText = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor(srgbRed: 0.38, green: 0.75, blue: 0.45, alpha: 1)
            : NSColor(srgbRed: 0.16, green: 0.48, blue: 0.23, alpha: 1)
    })

    /// 5.5:1 on white, 6.1:1 on the dark card.
    static let accentText = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor(srgbRed: 0.32, green: 0.66, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0, green: 0.4, blue: 0.83, alpha: 1)
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

    static let settingsCard = Color(nsColor: MainWindowNSPalette.settingsCard)
    static let settingsCardBorder = Color(nsColor: MainWindowNSPalette.settingsCardBorder)
    static let settingsDivider = Color(nsColor: MainWindowNSPalette.settingsDivider)
    static let settingsText = Color(nsColor: MainWindowNSPalette.settingsText)
    static let settingsSecondaryText = Color(nsColor: MainWindowNSPalette.settingsSecondaryText)
    /// Warning text. The system orange is 2.2:1 on white; this is 6.9:1.
    static let warningText = Color(nsColor: MainWindowNSPalette.warningText)
    static let errorText = Color(nsColor: MainWindowNSPalette.errorText)
    static let successText = Color(nsColor: MainWindowNSPalette.successText)
    static let accentText = Color(nsColor: MainWindowNSPalette.accentText)
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
    /// Settings rows in the flattened pages. Body, not callout: callout is 12pt
    /// against body's 13pt on macOS, which put the pages' own content a step
    /// below the sidebar's navigation labels.
    static let rowTitle = Font.body
    /// The Transcripts headline reads as a sentence, so it stays regular weight
    /// and leans on size alone.
    static let transcriptsHeadline = Font.system(.largeTitle, design: .default, weight: .regular)
    /// 26pt reads too loose at the system's default tracking; large text wants
    /// negative tracking the same way the small caps below want positive.
    static let transcriptsHeadlineTracking: CGFloat = -0.5
    /// A settings section heading: body size, semibold, sentence case.
    static let settingsSectionTitle = Font.body.weight(.semibold)
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
    static let metricValue = Font.system(.title, design: .rounded, weight: .semibold).monospacedDigit()
    static let emptyIcon = Font.system(size: 34, weight: .light)
}

enum AppMetrics {
    /// How opaque the detail pane's scrim is. 1 would kill the material
    /// entirely; this leaves just enough for the pane to still read as glass.
    static let detailPaneOpacity: Double = 0.9

    static let sidebarWidth: CGFloat = 208
    static let sidebarBrandTop: CGFloat = 24
    /// The brand icon is centered on the rows' icon column.
    static let sidebarBrandHorizontal: CGFloat = sidebarPaddingHorizontal + sidebarRowHorizontalPadding + (sidebarIconColumn - sidebarBrandIcon) / 2
    static let sidebarBrandBottom: CGFloat = 24
    static let sidebarBrandIcon: CGFloat = 24
    /// The brand name starts on the rows' text edge.
    static let sidebarBrandSpacing: CGFloat = sidebarPaddingHorizontal + sidebarTextInset - sidebarBrandHorizontal - sidebarBrandIcon
    static let sidebarPaddingHorizontal: CGFloat = 14
    static let sidebarRowSpacing: CGFloat = 2
    static let sidebarRowHorizontalPadding: CGFloat = 12
    static let sidebarIconColumn: CGFloat = 20
    static let sidebarIconSpacing: CGFloat = 12
    /// Where the text of a sidebar row starts: the row padding, the icon
    /// column and the gap after it.
    static let sidebarTextInset: CGFloat = sidebarRowHorizontalPadding + sidebarIconColumn + sidebarIconSpacing
    static let sidebarRowHeight: CGFloat = 32
    static let sidebarRowCornerRadius: CGFloat = 8
    static let sidebarFooterPadding: CGFloat = 18
    static let detailSpacing: CGFloat = 20
    static let detailPaddingHorizontal: CGFloat = 28
    static let detailPaddingTop: CGFloat = 24
    static let detailPaddingBottom: CGFloat = 24
    static let cardPadding: CGFloat = 12
    static let cardCornerRadius: CGFloat = 10
    /// Settings pages: the column stops growing past this width so rows stay
    /// readable when the window is wide.
    static let settingsColumnMaxWidth: CGFloat = 680
    static let settingsSectionSpacing: CGFloat = 28
    /// Row text starts this far inside the card; section headings and
    /// footers start at the same place.
    static let settingsRowInset: CGFloat = 14
    static let settingsRowVerticalPadding: CGFloat = 10
    static let settingsRowMinHeight: CGFloat = 44
    static let metricPanelCornerRadius: CGFloat = 12
    static let cardSectionSpacing: CGFloat = 12
    static let listRowVerticalPadding: CGFloat = 10
    static let emptyStateSpacing: CGFloat = 14
    static let emptyStateMinHeight: CGFloat = 280
    static let emptyStateMaxWidth: CGFloat = 420
    static let iconButtonSize: CGFloat = 24
}

enum SidebarRecordingDot {
    case recording
    case paused
}

/// What a sidebar row shows at its trailing edge.
enum SidebarRowAccessory: Equatable {
    /// A meeting recording, visible from any page.
    case recording(SidebarRecordingDot)
    /// Something on that page needs the user.
    case attention
    /// A short status, such as a download percentage.
    case status(String)
}

struct SidebarNavigationRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    /// The row's list has the keyboard focus: an accent edge shows where the
    /// arrow keys act.
    var showsFocus = false
    var accessory: SidebarRowAccessory?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppMetrics.sidebarIconSpacing) {
                Image(systemName: icon)
                    .font(AppTypography.sidebarIcon)
                    .frame(width: AppMetrics.sidebarIconColumn)
                    .foregroundStyle(isSelected ? Color.primary : MainWindowPalette.secondaryText)
                Text(title)
                    .font(isSelected ? AppTypography.sidebarLabelSelected : AppTypography.sidebarLabel)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                SidebarAccessoryView(accessory: accessory)
            }
            .padding(.horizontal, AppMetrics.sidebarRowHorizontalPadding)
            .padding(.vertical, 6)
            .frame(minHeight: AppMetrics.sidebarRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sidebarRowBackground(isSelected: isSelected, showsFocus: showsFocus)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The background every sidebar row shares: a fill for the hover and the
/// selection, and an accent edge while its list has the keyboard focus. A
/// field rests one step up, so it reads as a box before the pointer is on it.
private struct SidebarRowBackground: ViewModifier {
    let isSelected: Bool
    let showsFocus: Bool
    let isField: Bool

    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppMetrics.sidebarRowCornerRadius, style: .continuous)
        let resting = isSelected ? 2 : (isField ? 1 : 0)
        let level = min(2, resting + (isHovered ? 1 : 0))
        content
            .background(shape.fill(MainWindowPalette.selectedFill.opacity(Double(level) / 2)))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(showsFocus ? 0.55 : 0), lineWidth: 1))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    func sidebarRowBackground(isSelected: Bool = false, showsFocus: Bool = false, isField: Bool = false) -> some View {
        modifier(SidebarRowBackground(isSelected: isSelected, showsFocus: showsFocus, isField: isField))
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        // Reduced motion keeps the feedback and drops the geometry: the press
        // still dims, it just does not move. This is the shared style behind
        // the sidebar, the hotkey recorder and every icon button, so leaving
        // the scale in meant those users got motion everywhere else had
        // removed it.
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.1), value: configuration.isPressed)
    }
}

/// The dot or status at the end of a sidebar row.
struct SidebarAccessoryView: View {
    let accessory: SidebarRowAccessory?

    var body: some View {
        switch accessory {
        case let .recording(state):
            Circle()
                .fill(state == .paused ? Color.secondary : Color.red)
                .frame(width: 7, height: 7)
                .accessibilityLabel(state == .paused ? "Recording paused" : "Recording")
        case .attention:
            Circle()
                .fill(Color.orange)
                .frame(width: 7, height: 7)
                .accessibilityLabel("Needs attention")
        case let .status(text):
            Text(numbers: text)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
        case nil:
            EmptyView()
        }
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

struct DetailPageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.pageTitle)
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

struct InlineStatusBanner: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var progress: Double?
    /// Trailing button, for banners that can be acted on where they stand.
    var actionTitle: String?
    var action: (() -> Void)?
    /// False draws the trailing button bordered instead of filled.
    var actionIsProminent = true
    /// A bordered button before the trailing one, for a second choice.
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?
    /// Makes the whole banner a target, for banners that lead somewhere.
    var onTap: (() -> Void)?

    var body: some View {
        content
            .padding(14)
            // A soft wash of the severity colour instead of a bordered card.
            // The old tinted stroke plus a coloured title was two signals for
            // one fact, and it read as a leftover card on pages that are now
            // flat rows.
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                    .fill(tint.opacity(0.09))
            )
    }

    @ViewBuilder
    private var content: some View {
        if let onTap {
            Button(action: onTap) {
                banner
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.995))
        } else {
            banner
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(tint)

                // Only the icon carries the colour: a coloured headline on a
                // tinted ground is louder than the message needs to be.
                Text(numbers: title)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(Color.primary)

                Spacer(minLength: 12)

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if let actionTitle, let action {
                    if actionIsProminent {
                        Button(actionTitle, action: action)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Button(actionTitle, action: action)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            Text(numbers: detail)
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A permission or setup problem, rendered as the same banner the rest of the
/// window uses. It previously carried its own card, its own corner radius and a
/// type scale two steps smaller than everything around it.
struct AttentionTile: View {
    let item: AttentionItem
    let action: () -> Void
    let onFixAction: (AttentionItemFixAction) -> Void

    var body: some View {
        InlineStatusBanner(
            icon: item.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle",
            tint: item.severity == .error ? .red : .orange,
            title: item.title,
            detail: item.detail,
            actionTitle: item.fixAction?.title,
            action: item.fixAction.map { fixAction in
                { onFixAction(fixAction) }
            },
            onTap: action
        )
    }
}

struct EmptyStateCard<Action: View>: View {
    let icon: String
    let title: String
    let detail: String
    private let action: Action

    /// `action` shows under the detail, inside the centered group.
    init(icon: String, title: String, detail: String, @ViewBuilder action: () -> Action) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.action = action()
    }

    var body: some View {
        VStack(spacing: AppMetrics.emptyStateSpacing) {
            Image(systemName: icon)
                .font(AppTypography.emptyIcon)
                .foregroundStyle(Color.secondary.opacity(0.72))
            Text(numbers: title)
                .font(AppTypography.pageTitle)
            Text(numbers: detail)
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: AppMetrics.emptyStateMaxWidth)
            action
        }
        .frame(maxWidth: .infinity, minHeight: AppMetrics.emptyStateMinHeight)
    }
}

extension EmptyStateCard where Action == EmptyView {
    init(icon: String, title: String, detail: String) {
        self.init(icon: icon, title: title, detail: detail) { EmptyView() }
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
/// The devices that both microphone menus list, with the same names and the
/// chosen one checked. A device that is not connected cannot be chosen.
struct InputDevicePicker: View {
    let title: String
    let microphone: MicrophoneChoice

    var body: some View {
        Picker(
            title,
            selection: Binding(
                get: { microphone.selectedInputDeviceID },
                set: { microphone.selectedInputDeviceID = $0 }
            )
        ) {
            ForEach(microphone.menuChoices, id: \.self) { choice in
                Text(choice.title)
                    .tag(choice.id)
                    .disabled(!choice.isSelectable)
            }
        }
        .labelsHidden()
    }
}

struct SidebarInputDeviceRow: View {
    @Bindable var appState: AppState

    var body: some View {
        Menu {
            // Inline, so the menu checks the chosen device.
            InputDevicePicker(title: "Microphone", microphone: appState.microphone)
                .pickerStyle(.inline)
        } label: {
            // The same grid as the navigation rows: the icon in their icon
            // column, the name on their text edge.
            HStack(spacing: AppMetrics.sidebarIconSpacing) {
                Image(systemName: hasProblem ? "exclamationmark.triangle.fill" : "mic")
                    .font(AppTypography.sidebarIcon)
                    .frame(width: AppMetrics.sidebarIconColumn)
                    .foregroundStyle(hasProblem ? MainWindowPalette.warningText : MainWindowPalette.secondaryText)

                // The name gives up space first, so a long one never pushes
                // the chevron out and hides that this is a picker.
                Text(appState.microphone.activeInputDeviceName)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            .padding(.horizontal, AppMetrics.sidebarRowHorizontalPadding)
            .frame(minHeight: AppMetrics.sidebarRowHeight)
            .contentShape(Rectangle())
        }
        // A plain menu draws the label as given. The borderless style inset it
        // by its own amount, which moved the icon and name off the row grid.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // On the menu, not in its label: the menu takes the pointer events.
        .sidebarRowBackground()
        .help(appState.microphone.effectiveInputDeviceStatusText)
    }

    private var hasProblem: Bool {
        appState.microphone.hasNoInput
    }
}
