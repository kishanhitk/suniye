struct OnboardingMagicFormatProviderOption: Identifiable {
    let provider: OnboardingMagicFormatProvider
    let description: String
    let capabilityTags: [String]
    let isSelectable: Bool
    let unavailableHelpText: String?
    let canOpenSettings: Bool
    let primaryActionTitle: String

    var id: OnboardingMagicFormatProvider {
        provider
    }
}

@MainActor
struct OnboardingMagicFormatPresenter {
    let appState: AppState

    var options: [OnboardingMagicFormatProviderOption] {
        [localModelOption, appleIntelligenceOption]
    }

    var initialProvider: OnboardingMagicFormatProvider? {
        options.first(where: \.isSelectable)?.provider
    }

    func option(for provider: OnboardingMagicFormatProvider) -> OnboardingMagicFormatProviderOption? {
        options.first(where: { $0.provider == provider })
    }

    private var localModelOption: OnboardingMagicFormatProviderOption {
        let isInstalled = appState.localGemmaInstallState.isInstalled
        let isActive = appState.localGemmaInstallState.isActive
        let isReady = isInstalled && appState.localGemmaMagicFormatAvailability.isAvailable
        let isSelectable = appState.canSelectLocalGemmaDuringOnboarding
        let sizeText = appState.localGemmaModelEntry.expectedSizeText
        let description: String
        let primaryActionTitle: String

        if isReady {
            description = "Runs entirely on your Mac. Already installed and ready to use."
            primaryActionTitle = "Use Local Model & Continue"
        } else if isInstalled {
            description = "Runs entirely on your Mac. Installed, but setup needs attention."
            primaryActionTitle = "Local Model Unavailable"
        } else {
            description = "Runs entirely on your Mac. Requires a one-time \(sizeText) download."
            primaryActionTitle = isActive ? "Continue" : "Download \(sizeText) & Continue"
        }

        return OnboardingMagicFormatProviderOption(
            provider: .localModel,
            description: description,
            capabilityTags: ["Recommended", "Private", "Best formatting"],
            isSelectable: isSelectable,
            unavailableHelpText: isSelectable ? nil : appState.localGemmaMagicFormatAvailability.statusText,
            canOpenSettings: false,
            primaryActionTitle: primaryActionTitle
        )
    }

    private var appleIntelligenceOption: OnboardingMagicFormatProviderOption {
        let availability = appState.appleMagicFormatAvailability

        return OnboardingMagicFormatProviderOption(
            provider: .appleIntelligence,
            description: "Uses Apple's built-in model when available.",
            capabilityTags: ["On-device", "No additional download", "Less accurate"],
            isSelectable: availability.isAvailable,
            unavailableHelpText: availability.onboardingHelpText,
            canOpenSettings: availability == .appleIntelligenceNotEnabled,
            primaryActionTitle: "Use Apple Intelligence & Continue"
        )
    }
}

private extension AppleFoundationModelsAvailability {
    var onboardingHelpText: String? {
        switch self {
        case .available:
            return nil
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
}
