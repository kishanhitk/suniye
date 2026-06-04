import AppKit
import SwiftUI

struct OnboardingMagicFormatStepView: View {
    enum Choice: Equatable {
        case localModel
        case appleIntelligence
    }

    @Bindable var appState: AppState
    @State private var choice: Choice?

    init(appState: AppState) {
        self.appState = appState
        _choice = State(initialValue: Self.initialChoice(for: appState))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Make dictation cleaner")
                    .font(AppTypography.pageTitle)
                Text("Fix punctuation and add useful formatting before text is pasted.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    providerRow(
                        choice: .localModel,
                        title: "Local Model",
                        description: localModelDescription,
                        tags: ["Recommended", "Private", "Best formatting"],
                        isSelectable: appState.isLocalGemmaProviderSelectable
                    )

                    if !appState.isLocalGemmaProviderSelectable {
                        unavailableHelp(
                            text: "Local Model requires Apple Silicon.",
                            actionTitle: nil,
                            action: nil
                        )
                    }

                    CardDivider()
                        .padding(.horizontal, 14)

                    providerRow(
                        choice: .appleIntelligence,
                        title: "Apple Intelligence",
                        description: "Uses Apple's built-in model when available.",
                        tags: ["On-device", "No additional download", "Less accurate"],
                        isSelectable: appState.appleMagicFormatAvailability.isAvailable
                    )

                    if !appState.appleMagicFormatAvailability.isAvailable {
                        unavailableHelp(
                            text: appleIntelligenceHelpText,
                            actionTitle: appState.appleMagicFormatAvailability == .appleIntelligenceNotEnabled
                                ? "Open Settings"
                                : nil,
                            action: appState.appleMagicFormatAvailability == .appleIntelligenceNotEnabled
                                ? { appState.openAppleIntelligenceSettings() }
                                : nil
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Not Now") {
                    appState.skipMagicFormatDuringOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(MainWindowPalette.secondaryText)

                Spacer(minLength: 12)

                if let choice {
                    Button(primaryActionTitle(for: choice)) {
                        performPrimaryAction(for: choice)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isSelectable(choice))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func initialChoice(for appState: AppState) -> Choice? {
        if appState.isLocalGemmaProviderSelectable {
            return .localModel
        }
        if appState.appleMagicFormatAvailability.isAvailable {
            return .appleIntelligence
        }
        return nil
    }

    @ViewBuilder
    private func providerRow(
        choice rowChoice: Choice,
        title: String,
        description: String,
        tags: [String],
        isSelectable: Bool
    ) -> some View {
        let isSelected = choice == rowChoice
        let content = providerRowContent(
            choice: rowChoice,
            title: title,
            description: description,
            tags: tags,
            isSelected: isSelected,
            isSelectable: isSelectable
        )

        if isSelectable {
            Button {
                choice = rowChoice
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func providerRowContent(
        choice rowChoice: Choice,
        title: String,
        description: String,
        tags: [String],
        isSelected: Bool,
        isSelectable: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            providerIcon(for: rowChoice)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(Color.primary)

                Text(description)
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 5) {
                    ForEach(tags, id: \.self) { tag in
                        StylePageProviderTagBadge(title: tag)
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 12)

            StylePageRadioIndicator(isSelected: isSelected, isEnabled: isSelectable)
                .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? MainWindowPalette.selectedFill.opacity(0.8) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .opacity(isSelectable || isSelected ? 1 : 0.68)
    }

    private func providerIcon(for choice: Choice) -> some View {
        Group {
            switch choice {
            case .localModel:
                Image(systemName: "cpu")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.green.opacity(0.12))
                    )
            case .appleIntelligence:
                if appleIntelligenceSymbolName == "apple.intelligence" {
                    Image(systemName: "apple.intelligence")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(MainWindowPalette.selectedFill.opacity(0.75))
                        )
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.blue.opacity(0.12))
                        )
                }
            }
        }
    }

    private func unavailableHelp(
        text: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.leading, 56)
        .padding(.trailing, 14)
        .padding(.bottom, 12)
    }

    private var localModelDescription: String {
        if appState.localGemmaInstallState.isInstalled {
            return "Runs entirely on your Mac. Already installed and ready to use."
        }
        return "Runs entirely on your Mac. Requires a one-time \(appState.localGemmaModelEntry.expectedSizeText) download."
    }

    private var appleIntelligenceSymbolName: String {
        NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) == nil
            ? "sparkles"
            : "apple.intelligence"
    }

    private var appleIntelligenceHelpText: String {
        switch appState.appleMagicFormatAvailability {
        case .available:
            return "Apple Intelligence is ready."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings, then come back to Suniye."
        case .modelNotReady:
            return "Apple Intelligence is downloading or preparing its local model."
        case .deviceNotEligible:
            return "Apple Intelligence is not available on this Mac."
        case .unsupportedSDKOrRuntime:
            return "Apple Intelligence requires macOS 26 or newer."
        }
    }

    private func primaryActionTitle(for choice: Choice) -> String {
        switch choice {
        case .localModel:
            if appState.localGemmaInstallState.isInstalled {
                return "Use Local Model & Continue"
            }
            if appState.localGemmaInstallState.isActive {
                return "Continue"
            }
            return "Download \(appState.localGemmaModelEntry.expectedSizeText) & Continue"
        case .appleIntelligence:
            return "Use Apple Intelligence & Continue"
        }
    }

    private func isSelectable(_ choice: Choice) -> Bool {
        switch choice {
        case .localModel:
            return appState.isLocalGemmaProviderSelectable
        case .appleIntelligence:
            return appState.appleMagicFormatAvailability.isAvailable
        }
    }

    private func performPrimaryAction(for choice: Choice) {
        switch choice {
        case .localModel:
            appState.useLocalModelDuringOnboarding()
        case .appleIntelligence:
            appState.useAppleIntelligenceDuringOnboarding()
        }
    }
}
