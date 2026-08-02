import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CoreGraphicsComputerUseScreenshotService: ComputerUseScreenshotCapturing {
    private let imageProvider: (CGRect, CGWindowID) -> CGImage?

    init(
        imageProvider: @escaping (CGRect, CGWindowID) -> CGImage? = { bounds, windowID in
            CGWindowListCreateImage(
                bounds,
                [.optionIncludingWindow],
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            )
        }
    ) {
        self.imageProvider = imageProvider
    }

    func capture(window: ComputerUseWindow) throws -> ComputerUseScreenshot {
        guard !window.bounds.isEmpty,
              let image = imageProvider(window.bounds.cgRect, window.id),
              let data = Self.pngData(from: image) else {
            throw ComputerUseObservationError.screenshotUnavailable
        }

        return ComputerUseScreenshot(
            data: data,
            mimeType: "image/png",
            width: image.width,
            height: image.height,
            originX: window.bounds.x,
            originY: window.bounds.y,
            zIndex: window.layer
        )
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
