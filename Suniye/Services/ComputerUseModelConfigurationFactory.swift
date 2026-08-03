import Foundation

enum ComputerUseModelConfigurationFactory {
    static func make(
        settings: LLMSettings,
        apiKey: String?
    ) -> ComputerUseRemoteModelConfiguration? {
        guard settings.isEnabled,
              settings.provider == .openAICompatible,
              let endpointURL = settings.validatedEndpointURL,
              let modelID = settings.validatedModelId,
              let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }

        return ComputerUseRemoteModelConfiguration(
            endpointURL: endpointURL,
            modelID: modelID,
            apiKey: apiKey,
            // General text calls use short limits. Computer Use needs enough time
            // to inspect a window and produce a structured action.
            timeoutSeconds: max(
                settings.timeoutSeconds,
                ComputerUseRemoteModelDefaults.timeoutSeconds
            ),
            maxTokens: max(
                settings.maxTokens,
                ComputerUseRemoteModelDefaults.maxTokens
            )
        )
    }
}
