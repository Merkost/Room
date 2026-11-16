import AppKit
import SwiftUI

/// An eager strip bitmap: neither the mark nor its dynamic colours resolve again
/// when SwiftUI displays the light and dark previews beside one another.
@MainActor
struct RoomMenuBarPreview {
    let output: RoomMenuBarOutput
    let image: NSImage

    static func make(input: RoomMenuBarInput, format: RoomMenuBarFormat,
                     appearance: NSAppearance.Name, width: CGFloat = 320) -> Self {
        let output = RoomMenuBarPresentation.make(input, format: format)
        let size = NSSize(width: width.isFinite && width > 0 ? width : 320, height: 22)
        let scale: CGFloat = 2
        let pixelsWide = Int(ceil(size.width * scale))
        let pixelsHigh = Int(size.height * scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
              let pixels = bitmap.bitmapData,
              let context = CGContext(data: pixels, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8,
                bytesPerRow: bitmap.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            preconditionFailure("The menu bar preview bitmap could not be allocated.")
        }
        bitmap.size = size
        context.scaleBy(x: scale, y: scale)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        let drawingAppearance = NSAppearance(named: appearance) ?? NSAppearance.currentDrawing()
        drawingAppearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = graphics
            let background = resolved(NSColor(RoomTokens.Surface.canvas))
            background.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

            let button = NSStatusBarButton(frame: NSRect(origin: .zero, size: size))
            button.appearance = drawingAppearance
            button.isBordered = false
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            button.title = output.title
            button.imagePosition = output.icon == .none ? .noImage : output.title.isEmpty ? .imageOnly : .imageLeading
            button.imageHugsTitle = true
            button.contentTintColor = nil
            button.image = icon(for: output)
            button.draw(button.bounds)
            // The pocket's image renderer erases its hollow portion. Restore
            // the strip surface underneath any pixels that drawing cleared.
            context.saveGState()
            context.setBlendMode(.destinationOver)
            context.setFillColor(background.cgColor)
            context.fill(NSRect(origin: .zero, size: size))
            context.restoreGState()
        }
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = false
        image.accessibilityDescription = output.accessibilityValue
        return Self(output: output, image: image)
    }

    private static func resolved(_ color: NSColor) -> NSColor { color.usingColorSpace(.sRGB) ?? color }

    private static func tintColor(_ tint: RoomMenuBarTint) -> NSColor? {
        switch tint {
        case .none: nil
        case .normal: RoomTokens.Status.normalAppKit
        case .elevated: RoomTokens.Status.elevatedAppKit
        case .critical: RoomTokens.Status.criticalAppKit
        }
    }

    private static func icon(for output: RoomMenuBarOutput) -> NSImage? {
        switch output.icon {
        case .none:
            return nil
        case .mark:
            return RoomPocketMark.image(fill: output.pocketFill, pointSize: 16, tint: tintColor(output.tint))
        case .symbol:
            var image = NSImage(systemSymbolName: output.symbolName, accessibilityDescription: "Room")
            if let tint = tintColor(output.tint) {
                image = image?.withSymbolConfiguration(.init(paletteColors: [resolved(tint)]))
            } else {
                image?.isTemplate = true
            }
            image?.size = NSSize(width: 16, height: 16)
            return image
        }
    }
}
