import AppKit
import SwiftUI

enum MainWindowSection: String, CaseIterable, Hashable {
    case home
    case dictionary
    case style
    case notes
    case settings

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .dictionary:
            return "Dictionary"
        case .style:
            return "Style"
        case .notes:
            return "Notes"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "square.grid.2x2"
        case .dictionary:
            return "text.book.closed"
        case .style:
            return "textformat.alt"
        case .notes:
            return "note.text"
        case .settings:
            return "gearshape"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: MainWindowSection
    let isExpanded: Bool

    static let primarySections: [MainWindowSection] = [.home, .dictionary, .style, .notes, .settings]

    var body: some View {
        VStack(alignment: isExpanded ? .leading : .center, spacing: 16) {
            if isExpanded {
                HStack(spacing: 12) {
                    SuniyeBrandMark()
                    Text("Suniye")
                        .font(AppTypography.ui(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("Local")
                        .font(AppTypography.ui(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.subtleBackground)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                }
                .padding(.top, 4)
            } else {
                SuniyeBrandMark()
                    .padding(.top, 4)
            }

            VStack(alignment: isExpanded ? .leading : .center, spacing: 6) {
                ForEach(SidebarView.primarySections, id: \.self) { section in
                    SidebarNavButton(section: section, selection: $selection, isExpanded: isExpanded)
                }
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(AppLogger.shared.logFileURL.deletingLastPathComponent())
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                    if isExpanded {
                        Text("Help")
                            .font(AppTypography.ui(size: 14, weight: .medium))
                        Spacer()
                    }
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                        .fill(Color.clear)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isExpanded ? .topLeading : .top)
        .background(AppTheme.windowBackground)
    }
}

private struct SuniyeBrandMark: View {
    private let barHeights: [CGFloat] = [10, 18, 24, 18, 10]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(AppTheme.primaryText)
                    .frame(width: 3, height: height)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

private struct SidebarNavButton: View {
    let section: MainWindowSection
    @Binding var selection: MainWindowSection
    let isExpanded: Bool

    var body: some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                if isExpanded {
                    Text(section.title)
                        .font(AppTypography.ui(size: 17, weight: .medium))
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .foregroundStyle(selection == section ? AppTheme.primaryText : AppTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                    .fill(selection == section ? AppTheme.subtleBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}
