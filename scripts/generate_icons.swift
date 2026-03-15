import AppKit
import Foundation

struct Palette {
    static let background = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.96, alpha: 1.0)
    static let foreground = NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 1.0)
}

enum IconGenerator {
    static func drawAppIcon(size: Int) throws -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "generate_icons", code: 2, userInfo: [NSLocalizedDescriptionKey: "failed to allocate bitmap"])
        }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context

        let sizeF = CGFloat(size)
        let rect = NSRect(x: 0, y: 0, width: sizeF, height: sizeF)
        let radius = sizeF * 0.225

        let rounded = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        Palette.background.setFill()
        rounded.fill()

        let strokeInset = sizeF * 0.14
        let strokeRect = rect.insetBy(dx: strokeInset, dy: strokeInset)
        let strokePath = NSBezierPath()
        strokePath.lineCapStyle = .round
        strokePath.lineJoinStyle = .round
        strokePath.lineWidth = max(2.0, sizeF * 0.06)

        let centerY = strokeRect.midY
        let segment = strokeRect.width / 6.0

        strokePath.move(to: NSPoint(x: strokeRect.minX, y: centerY))
        strokePath.line(to: NSPoint(x: strokeRect.minX + segment, y: centerY + sizeF * 0.085))
        strokePath.line(to: NSPoint(x: strokeRect.minX + segment * 2.0, y: centerY - sizeF * 0.05))
        strokePath.line(to: NSPoint(x: strokeRect.minX + segment * 3.0, y: centerY + sizeF * 0.13))
        strokePath.line(to: NSPoint(x: strokeRect.minX + segment * 4.0, y: centerY - sizeF * 0.08))
        strokePath.line(to: NSPoint(x: strokeRect.minX + segment * 5.0, y: centerY + sizeF * 0.065))
        strokePath.line(to: NSPoint(x: strokeRect.maxX, y: centerY))

        Palette.foreground.setStroke()
        strokePath.stroke()

        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        return image
    }

    static func drawStatusIcon(size: Int) throws -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "generate_icons", code: 3, userInfo: [NSLocalizedDescriptionKey: "failed to allocate bitmap"])
        }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context

        let sizeF = CGFloat(size)

        let barWidth = max(1.5, sizeF * 0.115)
        let gap = max(1.2, sizeF * 0.08)
        let heights: [CGFloat] = [0.42, 0.82, 0.58, 0.94, 0.62]
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        var x = (sizeF - totalWidth) / 2.0

        Palette.foreground.setFill()
        for h in heights {
            let barHeight = sizeF * h
            let y = (sizeF - barHeight) / 2.0
            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2.0, yRadius: barWidth / 2.0).fill()
            x += barWidth + gap
        }

        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate_icons", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to generate png"])
    }
    try png.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDir = root.appendingPathComponent("Suniye/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let statusIconDir = root.appendingPathComponent("Suniye/Assets.xcassets/StatusBarIcon.imageset", isDirectory: true)
try FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: statusIconDir, withIntermediateDirectories: true)

let appSizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]
for size in appSizes {
    let image = try IconGenerator.drawAppIcon(size: size)
    let url = appIconDir.appendingPathComponent("icon_\(size)x\(size).png")
    try writePNG(image, to: url)
}

let statusSizes: [Int] = [16, 32]
for size in statusSizes {
    let image = try IconGenerator.drawStatusIcon(size: size)
    let url = statusIconDir.appendingPathComponent("status_\(size).png")
    try writePNG(image, to: url)
}
