import SwiftUI

/// The version and the update status at the bottom of the main window's
/// sidebar. It sits on the grid of the rows above it: the symbol in their icon
/// column, the text on their text edge.
struct SidebarUpdateRow: View {
    let appState: AppState

    @State private var isHovered = false

    var body: some View {
        let row = appState.updateRow
        let isActive = row.action != nil && row.isEnabled
        let actionTitle = isHovered && isActive ? row.actionTitle : nil

        Button {
            appState.performUpdateRowAction()
        } label: {
            HStack(spacing: AppMetrics.sidebarIconSpacing) {
                ZStack {
                    if actionTitle != nil {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    } else {
                        symbol(row.symbol)
                    }
                }
                .font(AppTypography.sidebarIcon)
                .frame(width: AppMetrics.sidebarIconColumn)

                Text(numbers: actionTitle ?? row.title)
                    .font(row.tone == .strong ? AppTypography.subheadlineSemibold : AppTypography.subheadline)
                    .foregroundStyle(actionTitle != nil ? Color.primary : color(for: row.tone))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppMetrics.sidebarRowHorizontalPadding)
            .frame(minHeight: AppMetrics.sidebarRowHeight)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: row)
            .animation(.easeOut(duration: 0.12), value: actionTitle)
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
        .disabled(!isActive)
        .opacity(row.isEnabled ? 1 : 0.45)
        .sidebarRowBackground(isRaised: row.tone == .strong, respondsToHover: isActive)
        .onHover { isHovered = $0 }
        .help(row.help ?? "")
        .accessibilityHint(row.actionTitle ?? "")
    }

    @ViewBuilder
    private func symbol(_ symbol: UpdateRow.Symbol?) -> some View {
        switch symbol {
        case .progress:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
        case .upToDate:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(MainWindowPalette.successText)
        case .available:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(MainWindowPalette.accentText)
        case .ready:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .warning:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(MainWindowPalette.warningText)
        case nil:
            Color.clear
                .frame(width: AppMetrics.sidebarIconColumn, height: 1)
        }
    }

    private func color(for tone: UpdateRow.Tone) -> Color {
        switch tone {
        case .quiet:
            return MainWindowPalette.secondaryText
        case .plain, .strong:
            return Color.primary
        case .warning:
            return MainWindowPalette.warningText
        }
    }
}
