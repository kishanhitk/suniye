import SwiftUI

struct OnboardingMagicFormatStepView: View {
    @Bindable var appState: AppState
    @State private var selectedProvider: OnboardingMagicFormatProvider?

    init(appState: AppState) {
        self.appState = appState
        _selectedProvider = State(
            initialValue: OnboardingMagicFormatPresenter(appState: appState).initialProvider
        )
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
                let options = presenter.options

                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        providerRow(option)

                        if index < options.count - 1 {
                            CardDivider()
                                .padding(.horizontal, 14)
                        }
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

                if let selectedOption {
                    Button(selectedOption.primaryActionTitle) {
                        appState.confirmMagicFormatDuringOnboarding(selectedOption.provider)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!selectedOption.isSelectable)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: presenter.initialProvider) { _, initialProvider in
            if selectedOption?.isSelectable != true {
                selectedProvider = initialProvider
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ option: OnboardingMagicFormatProviderOption) -> some View {
        if option.isSelectable {
            Button {
                selectedProvider = option.provider
            } label: {
                providerRowContent(option)
            }
            .buttonStyle(.plain)
        } else {
            providerRowContent(option)
        }

        if let helpText = option.unavailableHelpText {
            unavailableHelp(helpText, canOpenSettings: option.canOpenSettings)
        }
    }

    private func providerRowContent(_ option: OnboardingMagicFormatProviderOption) -> some View {
        let isSelected = selectedProvider == option.provider

        return HStack(alignment: .top, spacing: 12) {
            StylePageProviderIcon(
                provider: option.provider.magicFormatProvider
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(option.provider.magicFormatProvider.displayName)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(Color.primary)

                Text(option.description)
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 5) {
                    ForEach(option.capabilityTags, id: \.self) { tag in
                        StylePageProviderTagBadge(title: tag)
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 12)

            StylePageRadioIndicator(isSelected: isSelected, isEnabled: option.isSelectable)
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
        .opacity(option.isSelectable || isSelected ? 1 : 0.68)
    }

    private func unavailableHelp(_ text: String, canOpenSettings: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            if canOpenSettings {
                Button("Open Settings") {
                    appState.openAppleIntelligenceSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.leading, 56)
        .padding(.trailing, 14)
        .padding(.bottom, 12)
    }

    private var presenter: OnboardingMagicFormatPresenter {
        OnboardingMagicFormatPresenter(appState: appState)
    }

    private var selectedOption: OnboardingMagicFormatProviderOption? {
        selectedProvider.flatMap { presenter.option(for: $0) }
    }
}
