import Foundation

enum ComputerUseModelConfigurationFactory {
    static func make(
        settings: LLMSettings,
        apiKey: String?
    ) -> ComputerUseRemoteModelConfiguration? {
        guard let endpointURL = settings.validatedEndpointURL,
              let modelID = settings.validatedModelId,
              let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }

        return ComputerUseRemoteModelConfiguration(
            endpointURL: endpointURL,
            modelID: modelID,
            apiKey: apiKey
        )
    }
}
