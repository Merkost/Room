import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let canvas = CGSize(width: 2_880, height: 1_800)
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private struct RenderInputError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) { errorDescription = message }
}

private struct Shot: Decodable {
    let name: String
    let capture: String
    let headline: String
    let detail: String
    let tone: Tone
    let trimTopFraction: Double?
}

private enum Tone: String, Decodable {
    case paper, slate

    var top: CGColor { cgColor(self == .paper ? 0xEBF2F0 : 0x20343B) }
    var bottom: CGColor { cgColor(self == .paper ? 0xD4E6E8 : 0x111F25) }
    var title: CGColor { cgColor(self == .paper ? 0x182B31 : 0xF1F7F6) }
    var ink: CGColor { cgColor(self == .paper ? 0x3D5861 : 0xC1D4D8) }
    var rule: CGColor { cgColor(self == .paper ? 0x3D7482 : 0x7FB5C3, alpha: 0.16) }
}

private func cgColor(_ hex: Int, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

private func loadImage(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Trim only transparent padding around the capture. Preserve the native window and its corners.
private func trimWindowPadding(_ image: CGImage) -> CGImage {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: return image
    default: break
    }
    let width = image.width
    let height = image.height
    guard let pixels = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                 bytesPerRow: width * 4, space: colorSpace,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = pixels.data else { return image }
    pixels.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height {
        let line = bytes.advanced(by: y * pixels.bytesPerRow)
        for x in 0..<width where line[x * 4 + 3] > 192 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    guard maxX > minX, maxY > minY else { return image }
    let left = max(0, minX - 22), top = max(0, minY - 22)
    let right = min(width, maxX + 23), bottom = min(height, maxY + 23)
    return image.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top)) ?? image
}

private func drawText(_ text: String, x: CGFloat, fromTop: CGFloat, size: CGFloat,
                      weight: NSFont.Weight, tracking: CGFloat, color: CGColor, in context: CGContext) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        .font: font,
        .kern: tracking,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]))
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: canvas.height - fromTop - font.ascender)
    CTLineDraw(line, context)
}

private func drawBackground(_ tone: Tone, in context: CGContext) {
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [tone.top, tone.bottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height),
                               end: CGPoint(x: canvas.width, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Sparse orthogonal edges echo the floor plan in Room. Keep them outside the main content.
    context.setStrokeColor(tone.rule)
    context.setLineWidth(2)
    let lines = CGMutablePath()
    lines.move(to: CGPoint(x: 0, y: 842))
    lines.addLine(to: CGPoint(x: 216, y: 842))
    lines.addLine(to: CGPoint(x: 216, y: 0))
    lines.move(to: CGPoint(x: 0, y: 418))
    lines.addLine(to: CGPoint(x: 216, y: 418))
    lines.move(to: CGPoint(x: 2_664, y: 0))
    lines.addLine(to: CGPoint(x: 2_664, y: 1_385))
    lines.addLine(to: CGPoint(x: 2_880, y: 1_385))
    lines.move(to: CGPoint(x: 2_664, y: 585))
    lines.addLine(to: CGPoint(x: 2_880, y: 585))
    context.addPath(lines)
    context.strokePath()
}

private func render(_ shot: Shot, image: CGImage, icon: CGImage, to destination: URL) throws {
    let width = Int(canvas.width), height = Int(canvas.height)
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw CocoaError(.coderInvalidValue)
    }
    context.interpolationQuality = .high
    drawBackground(shot.tone, in: context)
    context.draw(icon, in: CGRect(x: 146, y: canvas.height - 158, width: 78, height: 78))
    drawText("Room", x: 233, fromTop: 98, size: 45, weight: .semibold,
             tracking: -0.9, color: shot.tone.title, in: context)
    drawText(shot.headline, x: 144, fromTop: 192, size: 109, weight: .medium,
             tracking: -4.7, color: shot.tone.title, in: context)
    drawText(shot.detail, x: 150, fromTop: 326, size: 42, weight: .regular,
             tracking: -0.65, color: shot.tone.ink, in: context)

    let content: CGImage
    if let fraction = shot.trimTopFraction {
        guard (0..<1).contains(fraction) else { throw RenderInputError("Invalid top crop for \(shot.name).") }
        let top = Int((Double(image.height) * fraction).rounded())
        guard let cropped = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: image.height - top)) else {
            throw RenderInputError("Could not crop \(shot.name).")
        }
        content = cropped
    } else {
        content = image
    }
    let window = trimWindowPadding(content)
    let target = CGRect(x: 148, y: 76, width: 2_584, height: 1_285)
    let scale = min(target.width / CGFloat(window.width), target.height / CGFloat(window.height))
    let size = CGSize(width: CGFloat(window.width) * scale, height: CGFloat(window.height) * scale)
    let frame = CGRect(x: (canvas.width - size.width) / 2, y: target.midY - size.height / 2,
                      width: size.width, height: size.height).integral
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -27), blur: 50,
                      color: cgColor(0x0E1D21, alpha: shot.tone == .paper ? 0.27 : 0.48))
    context.draw(window, in: frame)
    context.restoreGState()

    guard let flattened = context.makeImage(),
          let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let properties = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary
    CGImageDestinationAddImage(writer, flattened, properties)
    guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
}

private func run() throws {
    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let arguments = Array(CommandLine.arguments.dropFirst())
    let usage = "Usage: swift scripts/store-media/render-screenshots.swift <capture-directory> <output-directory> [manifest.json]"
    if arguments == ["--help"] { print(usage); return }
    guard (2...3).contains(arguments.count) else { throw RenderInputError(usage) }
    let captures = URL(fileURLWithPath: arguments[0], isDirectory: true)
    let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let manifest = arguments.count == 3 ? URL(fileURLWithPath: arguments[2]) : here.appendingPathComponent("shots.json")
    let iconURL = here.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Room-1024.png")
    guard let icon = loadImage(at: iconURL) else { throw RenderInputError("Could not load the Room icon from Resources/Room-1024.png.") }
    let shots = try JSONDecoder().decode([Shot].self, from: Data(contentsOf: manifest))
    guard !shots.isEmpty else { throw RenderInputError("Screenshot manifest is empty.") }
    let names = shots.map(\.name)
    let filenames = names + shots.map(\.capture)
    guard Set(names).count == names.count,
          filenames.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }) else {
        throw RenderInputError("Screenshot manifest needs unique output names and plain filenames.")
    }
    let inputs = try shots.map { shot in
        guard let image = loadImage(at: captures.appendingPathComponent(shot.capture)) else {
            throw RenderInputError("Missing or unreadable screenshot capture: \(shot.capture)")
        }
        return (shot, image)
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (shot, image) in inputs {
        let url = output.appendingPathComponent(shot.name + ".png")
        try render(shot, image: image, icon: icon, to: url)
        print("\(url.lastPathComponent) — 2880 × 1800")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
