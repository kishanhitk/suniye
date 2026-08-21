import SuniyeAnalytics
import SwiftUI

/// One permission as a settings row: label with an info tip, the state's
/// buttons (or a granted tick), and the one sentence that explains the state.
/// Onboarding and Settings › General both render this; the dashboard tile is
/// built from the same `PermissionPresentation`.
struct PermissionRow: View {
    @Bindable var appState: AppState
    let presentation: PermissionPresentation
    let askSurface: PermissionAskSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                SettingRowLabel(title: presentation.title, info: presentation.purpose)
                Spacer(minLength: 12)
                if presentation.isGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .accessibilityLabel("\(presentation.title) allowed")
                } else {
                    HStack(spacing: 8) {
                        if let secondary = presentation.secondary {
                            Button(secondary.label) {
                                appState.performPermissionAction(secondary, for: presentation.kind, askSurface: askSurface)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        if let primary = presentation.primary {
                            Button(primary.label) {
                                appState.performPermissionAction(primary, for: presentation.kind, askSurface: askSurface)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .accessibilityLabel("\(primary.label): \(presentation.title)")
                        }
                    }
                }
            }
            .font(AppTypography.rowTitle)

            if let detail = presentation.detail {
                Text(detail)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
    }
}
