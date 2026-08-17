import SwiftUI

struct MagicFormatProviderStatus {
    let text: String
    let color: Color
}

@MainActor
struct MagicFormatProviderPresenter {
    let appState: AppState

    var providerOptions: [MagicFormatProvider] {
        [.localGemma, .appleFoundationModels, .openAICompatible]
    }

    var displayedProviderSelection: MagicFormatProvider {
        guard appState.llmProvider == .automatic else {
            return appState.llmProvider
        }
        if appState.usesAppleMagicFormatSettings {
            return .appleFoundationModels
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return .localGemma
        }
        return .openAICompatible
    }

    var topStatusText: String {
        switch appState.magicFormatSetupState {
        case .ready:
            return "Ready - using \(activeFormatterName)"
        case .off:
            return "Off"
        case .needsAPIKey, .needsServiceSetup:
            return setupStatusText
        }
    }

    var setupStatusColor: Color {
        switch appState.magicFormatSetupState {
        case .off:
            return .gray
        case .needsAPIKey, .needsServiceSetup:
            return .orange
        case .ready:
            if appState.usesLocalMagicFormatSettings {
                return .green
            }
            return appState.isAPIMagicFormatSetupVerified ? .green : .blue
        }
    }

    var setupStatusText: String {
        if appState.usesAppleMagicFormatSettings {
            return appState.appleMagicFormatAvailability.isAvailable
                ? "Apple Intelligence ready"
                : appState.appleMagicFormatAvailability.statusText
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return appState.localGemmaMagicFormatAvailability.isAvailable
                ? "Local model ready"
                : appState.localGemmaInstallStatusText
        }
        if appState.isAPIMagicFormatSetupVerified {
            return "Connected and ready"
        }
        switch appState.magicFormatSetupState {
        case .off:
            return "Off"
        case .needsAPIKey:
            return "Add an API key to get started"
        case .needsServiceSetup:
            return "Check the connection settings below"
        case .ready:
            return "Run a connection test to verify"
        }
    }

    func isSelectable(_ provider: MagicFormatProvider) -> Bool {
        switch provider {
        case .appleFoundationModels:
            return appState.appleMagicFormatAvailability.isAvailable
        case .localGemma:
            return appState.isLocalGemmaProviderSelectable
        case .automatic:
            return false
        case .openAICompatible:
            return true
        }
    }

    func subtitle(for provider: MagicFormatProvider) -> String {
        switch provider {
        case .automatic:
            return "Chooses Apple Intelligence, local model, then API."
        case .appleFoundationModels:
            if !appState.appleMagicFormatAvailability.isAvailable {
                return appState.appleMagicFormatAvailability.statusText
            }
            return "Fast on-device formatting, less accurate than the local model."
        case .localGemma:
            return "Fastest local LLM formatter on this Mac."
        case .openAICompatible:
            return "Use your OpenAI-compatible endpoint."
        }
    }

    func capabilityTags(for provider: MagicFormatProvider) -> [String] {
        switch provider {
        case .automatic:
            return ["Local first", "Fallbacks"]
        case .appleFoundationModels:
            switch appState.appleMagicFormatAvailability {
            case .available:
                return ["On-device", "Fast", "Lower accuracy"]
            case .appleIntelligenceNotEnabled:
                return ["On-device", "Fast", "Needs setting"]
            case .modelNotReady:
                return ["On-device", "Fast", "Preparing"]
            case .deviceNotEligible, .unsupportedSDKOrRuntime:
                return ["On-device", "Unavailable", "Lower accuracy"]
            }
        case .localGemma:
            if !appState.isLocalGemmaProviderSelectable {
                return ["Recommended", "Fastest", "Apple Silicon only"]
            }

            switch appState.localGemmaInstallState {
            case .notInstalled, .failed:
                return ["Recommended", "Fastest", "Download once"]
            case .downloading:
                return ["Recommended", "Fastest", "Downloading"]
            case .verifying:
                return ["Recommended", "Fastest", "Verifying"]
            case .installed:
                return ["Recommended", "Fastest", "Private"]
            case .unavailable:
                return ["Recommended", "Fastest", "Runtime missing"]
            }
        case .openAICompatible:
            return ["Cloud/API", "Bring key", "Most flexible"]
        }
    }

    func status(for provider: MagicFormatProvider) -> MagicFormatProviderStatus {
        switch provider {
        case .automatic:
            switch appState.magicFormatSetupState {
            case .off:
                return MagicFormatProviderStatus(text: "Off", color: .gray)
            case .ready:
                return MagicFormatProviderStatus(text: "Ready", color: .green)
            case .needsAPIKey:
                return MagicFormatProviderStatus(text: "Needs key", color: .orange)
            case .needsServiceSetup:
                return MagicFormatProviderStatus(text: "Setup needed", color: .orange)
            }
        case .appleFoundationModels:
            switch appState.appleMagicFormatAvailability {
            case .available:
                return MagicFormatProviderStatus(text: "Ready", color: .green)
            case .appleIntelligenceNotEnabled:
                return MagicFormatProviderStatus(text: "Off", color: .orange)
            case .modelNotReady:
                return MagicFormatProviderStatus(text: "Preparing", color: .blue)
            case .deviceNotEligible:
                return MagicFormatProviderStatus(text: "Unsupported", color: .gray)
            case .unsupportedSDKOrRuntime:
                return MagicFormatProviderStatus(text: "Requires macOS 26", color: .gray)
            }
        case .localGemma:
            if !appState.isLocalGemmaProviderSelectable {
                return MagicFormatProviderStatus(text: "Requires Apple Silicon", color: .gray)
            }
            switch appState.localGemmaInstallState {
            case .unavailable:
                return MagicFormatProviderStatus(text: "Unavailable", color: .gray)
            case .notInstalled:
                return MagicFormatProviderStatus(text: "Not installed", color: .orange)
            case .downloading:
                return MagicFormatProviderStatus(text: "Downloading", color: .blue)
            case .verifying:
                return MagicFormatProviderStatus(text: "Verifying", color: .blue)
            case .installed:
                return appState.localGemmaMagicFormatAvailability.isAvailable
                    ? MagicFormatProviderStatus(text: "Ready", color: .green)
                    : MagicFormatProviderStatus(text: "Setup needed", color: .orange)
            case .failed:
                return MagicFormatProviderStatus(text: "Failed", color: .red)
            }
        case .openAICompatible:
            if appState.llmEndpointValidationError != nil || appState.llmModelValidationError != nil {
                return MagicFormatProviderStatus(text: "Invalid", color: .red)
            }
            if appState.isAPIMagicFormatSetupVerified {
                return MagicFormatProviderStatus(text: "Connected", color: .green)
            }
            return appState.hasLLMAPIKey
                ? MagicFormatProviderStatus(text: "Saved key", color: .blue)
                : MagicFormatProviderStatus(text: "Needs key", color: .orange)
        }
    }

    private var activeFormatterName: String {
        if appState.usesAppleMagicFormatSettings {
            return "Apple Intelligence"
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return "Local Model"
        }
        return "API Endpoint"
    }
}
