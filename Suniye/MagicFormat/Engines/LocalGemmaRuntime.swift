import Foundation

struct LocalGemmaRuntime: Equatable {
    let serverExecutableURL: URL
    let model: LocalLLMModelCatalogEntry
    let modelURL: URL
    let drafterURL: URL?

    /// The drafter is optional for the launch: a server that started before
    /// the drafter was installed serves until it stops.
    var launch: LlamaServerLaunch {
        LlamaServerLaunch(
            executableURL: serverExecutableURL,
            arguments: LocalGemmaDefaults.serverArguments(modelPath: modelURL.path),
            optionalArguments: drafterURL.map { LocalGemmaDefaults.drafterArguments(drafterPath: $0.path) } ?? [],
            modelName: model.displayName
        )
    }
}

enum LocalGemmaRuntimeResolution {
    case success(LocalGemmaRuntime)
    case failure(LocalGemmaAvailability)
}

struct LocalGemmaRuntimeLocator {
    let modelManager: LocalLLMModelManagerProtocol
    let fileManager: FileManager

    init(
        modelManager: LocalLLMModelManagerProtocol = LocalLLMModelManager(),
        fileManager: FileManager = .default
    ) {
        self.modelManager = modelManager
        self.fileManager = fileManager
    }

    func resolve() -> LocalGemmaRuntimeResolution {
        guard modelManager.isHardwareSupported else {
            return .failure(.unsupportedHardware)
        }
        guard modelManager.isInstalled(LocalGemmaDefaults.modelID),
              let modelURL = try? modelManager.modelFileURL(for: LocalGemmaDefaults.modelID) else {
            return .failure(.modelNotInstalled)
        }
        guard let serverURL = LlamaServer.locateExecutable(fileManager: fileManager) else {
            return .failure(.runtimeUnavailable)
        }
        return .success(LocalGemmaRuntime(
            serverExecutableURL: serverURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: modelURL,
            drafterURL: modelManager.drafterFileURL(for: LocalGemmaDefaults.modelID)
        ))
    }
}
