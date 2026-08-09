import Foundation

protocol ComputerUseScreenshotLoading: Sendable {
    func dataURL(for url: URL) async throws -> String
}

struct SystemComputerUseScreenshotLoader: ComputerUseScreenshotLoading {
    private static let maximumBytes = 25 * 1_024 * 1_024

    func dataURL(for url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= Self.maximumBytes else {
                throw ComputerUseScreenshotLoadError.tooLarge
            }
            let mimeType = switch url.pathExtension.lowercased() {
            case "png": "image/png"
            case "jpg", "jpeg": "image/jpeg"
            default: throw ComputerUseScreenshotLoadError.unsupportedType
            }
            return "data:\(mimeType);base64,\(data.base64EncodedString())"
        }.value
    }
}

private enum ComputerUseScreenshotLoadError: Error {
    case tooLarge
    case unsupportedType
}
