// Renders the background of the Finder window that Suniye.dmg opens: the
// instruction, the dotted arrow, and the monochrome landscape of the onboarding
// Welcome screen. Finder draws the app, the Applications alias and their labels
// on top, at the positions in packaging/dmg/dmgbuild_settings.py.
//
// Writes background.png (660 × 432) and background@2x.png (1320 × 864) into the
// output directory. dmgbuild combines them into one HiDPI TIFF.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The window content of the design, in points.
let design = CGSize(width: 660, height: 400)

/// The image size. Finder's window bounds include the title bar, and Finder tiles
/// the image when the content area is taller than it. dmgbuild_settings.py makes
/// the window 432 pt tall: the 400 pt design under a 32 pt title bar (macOS 27).
/// Under a shorter title bar the content area is taller, so the hills continue
/// down the full 432 pt and fill it.
let canvas = CGSize(width: 660, height: 432)

/// The landscape ink of the onboarding Welcome screen, #3A5A8C.
func ink(_ opacity: CGFloat) -> CGColor {
    CGColor(srgbRed: 0x3A / 255, green: 0x5A / 255, blue: 0x8C / 255, alpha: opacity)
}

func rgb(_ hex: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Builds a path from SVG path data with absolute M, L, Q, C and Z commands, the
/// subset the design uses, offset by `origin`.
func svgPath(_ data: String, at origin: CGPoint) -> CGPath {
    var commands: [(name: Character, values: [CGFloat])] = []
    var number = ""
    func endNumber() {
        guard !number.isEmpty else { return }
        guard let value = Double(number), !commands.isEmpty else {
            preconditionFailure("Malformed SVG path data: \(data)")
        }
        commands[commands.count - 1].values.append(CGFloat(value))
        number = ""
    }
    for character in data {
        if character.isLetter {
            endNumber()
            commands.append((character, []))
        } else if character == " " || character == "," {
            endNumber()
        } else {
            number.append(character)
        }
    }
    endNumber()

    let arities: [Character: Int] = ["M": 2, "L": 2, "Q": 4, "C": 6, "Z": 0]
    let path = CGMutablePath()
    for (name, values) in commands {
        guard let arity = arities[name],
              arity == 0 ? values.isEmpty : !values.isEmpty && values.count.isMultiple(of: arity) else {
            preconditionFailure("Unsupported SVG path command \(name) in: \(data)")
        }
        let points = stride(from: 0, to: values.count, by: 2).map {
            CGPoint(x: origin.x + values[$0], y: origin.y + values[$0 + 1])
        }
        switch name {
        case "M":
            // Pairs after the first are implicit line-tos.
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
        case "L":
            points.forEach { path.addLine(to: $0) }
        case "Q":
            for i in stride(from: 0, to: points.count, by: 2) {
                path.addQuadCurve(to: points[i + 1], control: points[i])
            }
        case "C":
            for i in stride(from: 0, to: points.count, by: 3) {
                path.addCurve(to: points[i + 2], control1: points[i], control2: points[i + 1])
            }
        default:
            path.closeSubpath()
        }
    }
    return path
}

func fill(_ data: String, at origin: CGPoint, color: CGColor, in context: CGContext) {
    context.addPath(svgPath(data, at: origin))
    context.setFillColor(color)
    context.fillPath()
}

func stroke(
    _ data: String,
    at origin: CGPoint,
    color: CGColor,
    width: CGFloat,
    cap: CGLineCap = .butt,
    join: CGLineJoin = .miter,
    dash: [CGFloat] = [],
    in context: CGContext
) {
    context.saveGState()
    context.addPath(svgPath(data, at: origin))
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(cap)
    context.setLineJoin(join)
    context.setLineDash(phase: 0, lengths: dash)
    context.strokePath()
    context.restoreGState()
}

/// Draws one line of system-font text centred across the window, with the top
/// of its line box at `top`, the way the design's CSS places it.
func drawCentredText(_ text: String, top: CGFloat, size: CGFloat, color: CGColor, in context: CGContext) {
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let attributes = [kCTFontAttributeName as String: font, kCTForegroundColorAttributeName as String: color] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)!)
    var ascent: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, nil, nil)
    // The context is flipped to top-left coordinates; flip the glyphs back upright.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: (canvas.width - width) / 2, y: top + ascent)
    CTLineDraw(line, context)
}

/// Draws the design in window points, origin at the top left.
func drawBackground(in context: CGContext) {
    context.setFillColor(rgb(0xFAFAFA))
    context.fill(CGRect(origin: .zero, size: canvas))

    // Mountains: a 660 × 150 band along the bottom of the design, far ridge to
    // near hill. All three hills reach its bottom edge.
    let mountains = CGPoint(x: 0, y: design.height - 150)
    fill(
        "M0 96 L40 88 L80 80 L118 84 L158 70 L196 60 L224 52 L246 46 L266 54 L290 40 L318 22 L342 36 L366 32 L390 50 L424 60 L460 52 L490 58 L530 70 L574 78 L620 86 L660 92 L660 150 L0 150 Z",
        at: mountains, color: ink(0.06), in: context
    )
    stroke("M290 40 L318 22 L342 36 M224 52 L246 46 L266 54", at: mountains, color: ink(0.09), width: 1, join: .round, in: context)
    fill("M0 108 C80 92 160 96 240 104 C320 112 400 90 480 96 C560 102 620 110 660 104 L660 150 L0 150 Z", at: mountains, color: ink(0.08), in: context)
    fill("M0 130 C110 118 220 122 330 130 C440 138 550 124 660 120 L660 150 L0 150 Z", at: mountains, color: ink(0.10), in: context)
    // The hills continue below the design to the bottom of the image; see `canvas`.
    let belowDesign = CGRect(x: 0, y: design.height, width: canvas.width, height: canvas.height - design.height)
    for opacity in [0.06, 0.08, 0.10] {
        context.setFillColor(ink(opacity))
        context.fill(belowDesign)
    }

    let birds = CGPoint(x: 500, y: 40)
    for (data, opacity) in [
        ("M2 12 Q6 6 10 10 Q14 6 18 12", 0.30),
        ("M26 6 Q29 2 32 5 Q35 2 38 6", 0.24),
        ("M40 18 Q43 14 46 17 Q49 14 52 18", 0.22),
        ("M70 24 Q72 21 74 23 Q76 21 78 24", 0.18),
    ] {
        stroke(data, at: birds, color: ink(opacity), width: 1.2, cap: .round, in: context)
    }

    drawCentredText("Drag Suniye into Applications", top: 46, size: 13, color: rgb(0x6E6E73), in: context)

    // A dotted arc from the app icon at (180, 170) to Applications at (480, 170).
    let arrow = CGPoint(x: 255, y: 150)
    stroke("M4 30 C40 6 110 6 140 26", at: arrow, color: ink(0.40), width: 1.6, cap: .round, dash: [1, 7], in: context)
    stroke("M131 18 L141 27 L128 30", at: arrow, color: ink(0.45), width: 1.6, cap: .round, join: .round, in: context)
}

func writePNG(scale: Int, to url: URL) -> Bool {
    let width = Int(canvas.width) * scale
    let height = Int(canvas.height) * scale
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else {
        return false
    }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    drawBackground(in: context)

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: render_dmg_background.swift <output-directory>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write(Data("Cannot create \(outputDirectory.path): \(error)\n".utf8))
    exit(1)
}

for (scale, name) in [(1, "background.png"), (2, "background@2x.png")] {
    let url = outputDirectory.appendingPathComponent(name)
    guard writePNG(scale: scale, to: url) else {
        FileHandle.standardError.write(Data("Cannot render \(url.path).\n".utf8))
        exit(1)
    }
    print("Rendered \(url.path)")
}
