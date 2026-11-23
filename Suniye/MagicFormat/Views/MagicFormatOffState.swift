import SwiftUI

/// Off: the page is the before-and-after and one button.
///
/// No HEARD/PASTED labels, no chip row naming the changes — the arrow
/// says which is which and the text shows the rest. Existing settings stay
/// listed but dim and without chevrons, so nothing looks deleted while nothing
/// invites a change that could not take effect.
struct MagicFormatOffState: View {
    @Bindable var appState: AppState
    let onTurnOn: () -> Void

    private static let heard = "hey jacob comma new line quick update on the migration um three things we still need first move the postgres call into the g r p c service second um backfill the old rows and third rename the flag to enable dot new dot sync uh let's ship it thursday no actually friday the fourth because staging is down till then thanks rocket emoji"

    var body: some View {
        SettingsSection {
            SettingsCustomRow {
                demonstration
                    .padding(.vertical, 6)
            }
            SettingsCustomRow {
                callToAction
            }
        }

        SettingsSection {
            dimmedSettings
        }
    }

    private var demonstration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.heard)
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.settingsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "arrow.down")
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.tertiaryText)
                .accessibilityLabel("becomes")

            pasted
        }
    }

    private var pasted: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hey Jacob,")
            Text("Quick update on the migration. Three things we still need:")
            Text("1. Move the PostgreSQL call into the gRPC service")
            Text("2. Backfill the old rows")
            HStack(spacing: 0) {
                Text("3. Rename the flag to ")
                Text("enable.new.sync")
                    .font(AppTypography.codeBody)
            }
            Text("")
            Text("Let's ship it Friday the 4th, because staging is down till then. Thanks \u{1F680}")
        }
        .font(AppTypography.rowTitle)
        .foregroundStyle(Color.primary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var callToAction: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button("Turn On", action: onTurnOn)
                .buttonStyle(.borderedProminent)
                .settingsControlAnchor(.magicFormat)
                .disabled(needsDownload && !appState.canStartLocalGemmaDownload)

            Text(numbers: costText)
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var needsDownload: Bool {
        switch appState.localGemmaInstallState {
        case .installed, .unavailable:
            return false
        case .notInstalled, .downloading, .verifying, .failed:
            return true
        }
    }

    /// The real cost only. Nothing about added latency — it is not measured.
    private var costText: String {
        needsDownload
            ? "Downloads the local model once, \(appState.localGemmaModelEntry.expectedSizeText), and runs entirely on this Mac."
            : "Uses the local model already on this Mac."
    }

    /// Listed, not offered.
    @ViewBuilder
    private var dimmedSettings: some View {
        DisclosureSettingRow(title: "Engine", value: engineValue, isEnabled: false)
        DisclosureSettingRow(title: "Base instructions", value: "Default", isEnabled: false)
        DisclosureSettingRow(
            title: "App-specific writing style",
            value: appPromptSummary,
            isEnabled: false
        )
    }

    private var engineValue: String {
        appState.localGemmaInstallState.isInstalled
            ? appState.localGemmaModelEntry.displayName
            : "Local model"
    }

    private var appPromptSummary: String {
        let count = appState.llmAppPromptBindings.count
        guard count > 0 else {
            return "None"
        }
        return count == 1 ? "1 app" : "\(count) apps"
    }
}
