import SwiftUI

struct AppShellCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(AppTheme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.panelCornerRadius, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.panelCornerRadius, style: .continuous))
    }
}

struct SectionHeaderRow: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTypography.ui(size: 44, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryDarkButtonStyle())
            }
        }
    }
}

struct HeroCalloutCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(AppTypography.serif(size: 52, weight: .regular))
                .foregroundStyle(AppTheme.primaryText)

            Text(subtitle)
                .font(AppTypography.ui(size: 30, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            content
        }
        .padding(24)
        .background(AppTheme.warmCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.panelCornerRadius, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.panelCornerRadius, style: .continuous))
    }
}

struct MetricPill: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(symbol)
                .font(AppTypography.ui(size: 14))
            Text(label)
                .font(AppTypography.ui(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(AppTypography.ui(size: 19, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.subtleBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

struct DataTableCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(AppTheme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.panelCornerRadius, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.panelCornerRadius, style: .continuous))
    }
}

struct RowActionButton: View {
    let title: String
    let role: ButtonRole?
    let style: RowActionStyle
    let action: () -> Void

    enum RowActionStyle {
        case primary
        case soft
    }

    init(title: String, role: ButtonRole? = nil, style: RowActionStyle = .soft, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
        }
        .buttonStyle(style == .primary ? AnyButtonStyle(PrimaryDarkButtonStyle()) : AnyButtonStyle(SoftPillButtonStyle()))
    }
}

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.ui(size: 13, weight: .medium))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                    .fill(AppTheme.subtleBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AppTypography.ui(size: 21, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.ui(size: 15))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 16)
    }
}

private struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}
