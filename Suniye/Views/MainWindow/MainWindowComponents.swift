import AppKit
import SwiftUI

private extension NSAppearance {
    var usesDarkMainWindowPalette: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private enum MainWindowNSPalette {
    static let baseSurface = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? .windowBackgroundColor
            : NSColor(calibratedWhite: 0.978, alpha: 1)
    })

    static let elevatedSurface = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette ? .controlBackgroundColor : .white
    })

    static let divider = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.06)
    })

    static let stroke = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.usesDarkMainWindowPalette
            ? NSColor.white.withAlphaComponent(0.1)
            : NSColor.black.withAlphaComponent(0.07)
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
    static let sidebarBackground = Color(nsColor: MainWindowNSPalette.baseSurface)
    static let sidebarTitle = Color.primary.opacity(0.24)
    static let divider = Color(nsColor: MainWindowNSPalette.divider)
    static let cardBackground = Color(nsColor: MainWindowNSPalette.elevatedSurface)
    static let editorBackground = Color(nsColor: MainWindowNSPalette.elevatedSurface)
    static let cardStroke = Color(nsColor: MainWindowNSPalette.stroke)
    static let selectedFill = Color(nsColor: MainWindowNSPalette.selection)
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.76)
    static let destructive = Color.red.opacity(0.78)
}

enum AppTypography {
    static let appTitle = Font.title2.weight(.semibold)
    static let sidebarIcon = Font.body.weight(.medium)
    static let sidebarLabel = Font.body
    static let sidebarLabelSelected = Font.body.weight(.semibold)
    static let pageTitle = Font.title2.weight(.semibold)
    static let sectionHeading = Font.headline.weight(.semibold)
    static let body = Font.body
    static let bodyMedium = Font.body.weight(.medium)
    static let subheadline = Font.subheadline
    static let subheadlineSemibold = Font.subheadline.weight(.semibold)
    static let caption = Font.caption
    static let callout = Font.callout
    static let calloutMedium = Font.callout.weight(.medium)
    static let codeBody = Font.system(.body, design: .monospaced)
    static let codeBodyMedium = Font.system(.body, design: .monospaced).weight(.medium)
    static let codeCalloutSemibold = Font.system(.callout, design: .monospaced).weight(.semibold)
    static let metricValue = Font.system(size: 34, weight: .medium, design: .rounded)
    static let emptyIcon = Font.system(size: 34, weight: .light)
}

enum AppMetrics {
    static let sidebarWidth: CGFloat = 228
    static let sidebarBrandTop: CGFloat = 24
    static let sidebarBrandHorizontal: CGFloat = 24
    static let sidebarBrandBottom: CGFloat = 24
    static let sidebarPaddingHorizontal: CGFloat = 14
    static let sidebarRowSpacing: CGFloat = 4
    static let sidebarRowHorizontalPadding: CGFloat = 12
    static let sidebarRowHeight: CGFloat = 36
    static let sidebarRowCornerRadius: CGFloat = 8
    static let detailSpacing: CGFloat = 20
    static let detailPaddingHorizontal: CGFloat = 28
    static let detailPaddingTop: CGFloat = 24
    static let detailPaddingBottom: CGFloat = 24
    static let cardPadding: CGFloat = 12
    static let cardCornerRadius: CGFloat = 10
    static let metricCardPadding: CGFloat = 18
    static let metricCardSpacing: CGFloat = 18
    static let metricValueSpacing: CGFloat = 6
    static let metricCardMinHeight: CGFloat = 128
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(AppTypography.sidebarIcon)
                    .frame(width: 18)
                Text(section.title)
                    .font(isSelected ? AppTypography.sidebarLabelSelected : AppTypography.sidebarLabel)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : MainWindowPalette.secondaryText)
            .padding(.horizontal, AppMetrics.sidebarRowHorizontalPadding)
            .frame(height: AppMetrics.sidebarRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.sidebarRowCornerRadius, style: .continuous)
                    .fill(isSelected ? MainWindowPalette.selectedFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                .fill(MainWindowPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
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
    var tint: Color = MainWindowPalette.secondaryText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppTypography.bodyMedium)
                .frame(width: AppMetrics.iconButtonSize, height: AppMetrics.iconButtonSize)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

struct DashboardMetricCard: View {
    let icon: String
    let iconTint: Color
    let value: String
    let label: String

    var body: some View {
        SurfaceCard(padding: AppMetrics.metricCardPadding) {
            VStack(alignment: .leading, spacing: AppMetrics.metricCardSpacing) {
                Image(systemName: icon)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(iconTint)

                VStack(alignment: .leading, spacing: AppMetrics.metricValueSpacing) {
                    Text(value)
                        .font(AppTypography.metricValue)
                    Text(label)
                        .font(AppTypography.body)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppMetrics.metricCardMinHeight, alignment: .leading)
        }
    }
}

struct AttentionTile: View {
    let item: AttentionItem
    let action: () -> Void

    var body: some View {
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
        .buttonStyle(.plain)
    }
}

struct TranscriptSummaryRow: View {
    let result: RecentResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.text)
                .font(AppTypography.calloutMedium)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(result.createdAt.relativeTimestamp)  •  \(result.durationSeconds.shortSecondsString)")
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
        .padding(.vertical, AppMetrics.listRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MainWindowPalette.divider)
                .frame(height: 1)
        }
    }
}

struct TranscriptHistoryRow: View {
    let result: RecentResult
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(result.createdAt.relativeTimestamp)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                Text("•")
                    .foregroundStyle(MainWindowPalette.tertiaryText)
                Text(result.durationSeconds.shortSecondsString)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                Spacer(minLength: 0)
                ActionIconButton(systemName: "doc.on.doc", action: onCopy)
                ActionIconButton(systemName: "trash", tint: MainWindowPalette.destructive, action: onDelete)
            }

            Text(result.text)
                .font(AppTypography.callout)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppMetrics.listRowVerticalPadding)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MainWindowPalette.divider)
                .frame(height: 1)
        }
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
                .font(.title2.weight(.semibold))
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

    var compactDurationString: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        if minutes == 0 {
            return "\(seconds)s"
        }
        if seconds == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(seconds)s"
    }
}

extension Int {
    var abbreviatedString: String {
        switch self {
        case 0..<1000:
            return "\(self)"
        case 1000..<10_000:
            return String(format: "%.1fk", Double(self) / 1000).replacingOccurrences(of: ".0", with: "")
        default:
            return ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .decimal)
                .replacingOccurrences(of: " bytes", with: "")
        }
    }
}
