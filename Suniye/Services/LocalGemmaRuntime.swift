import Foundation

struct LocalGemmaRuntime: Equatable {
    let serverExecutableURL: URL
    let model: LocalLLMModelCatalogEntry
    let modelURL: URL
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
        guard let serverURL = findExecutable(named: "llama-server") else {
            return .failure(.runtimeUnavailable)
        }
        return .success(LocalGemmaRuntime(
            serverExecutableURL: serverURL,
            model: LocalGemmaDefaults.modelEntry,
            modelURL: modelURL
        ))
    }

    private func findExecutable(named name: String) -> URL? {
        if let override = ProcessInfo.processInfo.environment["SUNIYE_LLAMA_SERVER_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let bundleCandidates = [
            Bundle.main.url(forAuxiliaryExecutable: name),
            Bundle.main.url(forResource: name, withExtension: nil),
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "LocalLLM"),
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "LocalLLM/bin"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(name),
        ].compactMap { $0 }

        return bundleCandidates
            .lazy
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
