import AppKit
import Foundation
import ScreenCaptureKit

actor SystemComputerUseScreenshotCapturer: ComputerUseScreenshotCapturing {
    private let directory: URL
    private var latestURLByWindowID: [UInt32: URL] = [:]

    init(directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SuniyeComputerUse", isDirectory: true)) {
        self.directory = directory
    }

    func capture(windowID: UInt32) async throws -> ComputerUseCapturedScreenshot? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        let window = content.windows.first(where: {
            $0.windowID == windowID
        })
        guard let window else {
            throw ComputerUseScreenshotError.windowUnavailable(windowID)
        }
        let backingScale = await MainActor.run {
            NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?
                .backingScaleFactor ?? 1
        }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * backingScale))
        configuration.height = max(1, Int(window.frame.height * backingScale))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            )
        } catch {
            guard let fallbackImage = SuniyeCopyWindowImage(windowID, window.frame) else {
                throw error
            }
            image = fallbackImage
        }
        let pixelWidth = image.width
        let pixelHeight = image.height
        guard let data = NSBitmapImageRep(cgImage: image).representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.82]
        ) else {
            throw ComputerUseScreenshotError.encodingFailed
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        if let previousURL = latestURLByWindowID.updateValue(url, forKey: windowID) {
            try? FileManager.default.removeItem(at: previousURL)
        }
        return ComputerUseCapturedScreenshot(
            url: url,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            coordinateScale: window.frame.width / Double(pixelWidth),
            windowFrame: window.frame
        )
    }
}

enum ComputerUseScreenshotError: LocalizedError, Equatable, Sendable {
    case windowUnavailable(UInt32)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case let .windowUnavailable(id):
            "Window \(id) is unavailable for capture."
        case .encodingFailed:
            "Could not encode the window screenshot."
        }
    }
}
