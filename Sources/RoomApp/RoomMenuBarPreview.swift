import AppKit
import SwiftUI

/// An eager strip bitmap: neither the mark nor its dynamic colours resolve again
/// when SwiftUI displays the light and dark previews beside one another.
@MainActor
struct RoomMenuBarPreview {
    let output: RoomMenuBarOutput
    let image: NSImage

    /// The fixed Settings samples are decimal gigabytes, matching their captioned figures.
    nonisolated static let settingsFormat = RoomMenuBarFormat(
        memory: { decimalGigabytes($0, decimals: 1) },
        disk: { decimalGigabytes($0, decimals: 0) })

    nonisolated private static func decimalGigabytes(_ bytes: Int64, decimals: Int) -> String {
        var number = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"),
            decimals, Double(bytes) / 1_000_000_000)
        if number.hasSuffix(".0") { number.removeLast(2) }
        return number + " GB"
    }

    /// `.all` is the whole strip. The Settings grid draws `.surfaceAndClock` once and cross-fades only `.itemOnly` on top,
    /// so a change never dips to the page colour and the clock never flickers.
    enum Layers: Sendable { case all, surfaceAndClock, itemOnly }

    static func make(input: RoomMenuBarInput, format: RoomMenuBarFormat,
                     appearance: NSAppearance.Name, width: CGFloat = 320, layers: Layers = .all) -> Self {
        let output = RoomMenuBarPresentation.make(input, format: format)
        let size = NSSize(width: width.isFinite && width > 0 ? width : 320, height: stripHeight)
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
            // The board's strip (`.mbstrip`): menu-bar surface, items right-aligned, then the clock.
            // NSStatusBarButton.draw(_:) draws nothing off the status bar (measured: every strip came out blank),
            // so the item is laid out here with the same 13 pt medium digits, 16 pt icon and 5 pt gap the real item has.
            let dark = appearance == .darkAqua
            let background = Self.surface(for: appearance)
            let ink = dark ? Self.darkInk : Self.lightInk
            if layers != .itemOnly {
                background.setFill()
                NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
            }

            let attributes = Self.textAttributes(ink: ink)
            let clock = NSAttributedString(string: Self.clockText, attributes: attributes)
            let title = NSAttributedString(string: output.title, attributes: attributes)
            let frames = Self.frames(for: output, width: size.width)
            if layers != .itemOnly { clock.draw(at: frames.clock.origin) }
            if layers != .surfaceAndClock {
                if let iconFrame = frames.icon, let iconImage = icon(for: output, ink: ink) {
                    iconImage.draw(in: iconFrame)
                }
                if let titleFrame = frames.title { title.draw(at: titleFrame.origin) }
            }
            // The pocket's image renderer erases its hollow portion. Restore
            // the strip surface underneath any pixels that drawing cleared.
            if layers == .all {
                context.saveGState()
                context.setBlendMode(.destinationOver)
                context.setFillColor(background.cgColor)
                context.fill(NSRect(origin: .zero, size: size))
                context.restoreGState()
            }
        }
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = false
        image.accessibilityDescription = output.accessibilityValue
        return Self(output: output, image: image)
    }

    /// The menu-bar surface behind a strip, for the layered Settings grid.
    static func surface(for appearance: NSAppearance.Name) -> NSColor {
        appearance == .darkAqua ? darkSurface : lightSurface
    }

    private static func textAttributes(ink: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium), .foregroundColor: ink]
    }

    /// Where the clock, title and icon sit in a strip of this width, in points from the bottom-left (shared by drawing and tests).
    static func frames(for output: RoomMenuBarOutput, width: CGFloat)
        -> (clock: CGRect, title: CGRect?, icon: CGRect?) {
        let attributes = textAttributes(ink: .black)
        let clockSize = NSAttributedString(string: clockText, attributes: attributes).size()
        let titleSize = output.title.isEmpty ? .zero : NSAttributedString(string: output.title, attributes: attributes).size()
        let layout = ItemLayout(iconWidth: output.icon == .none ? 0 : iconPoints,
            titleWidth: ceil(titleSize.width), clockWidth: ceil(clockSize.width), stripWidth: width)
        func y(_ height: CGFloat) -> CGFloat { ((stripHeight - height) / 2).rounded() }
        return (CGRect(x: layout.clockX, y: y(clockSize.height), width: ceil(clockSize.width), height: clockSize.height),
                output.title.isEmpty ? nil : CGRect(x: layout.titleX, y: y(titleSize.height), width: ceil(titleSize.width), height: titleSize.height),
                output.icon == .none ? nil : CGRect(x: layout.iconX, y: y(iconPoints), width: iconPoints, height: iconPoints))
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

    /// Board `.mbstrip`: 24 pt high; `--mb-light` #DCE3E7 with ink #222527, `--mb-dark` #1E2224 with ink #F3F5F6.
    static let stripHeight: CGFloat = 24
    static let clockText = "11:04"
    static let iconPoints: CGFloat = 16
    private static let lightSurface = NSColor(srgbRed: 0xDC / 255, green: 0xE3 / 255, blue: 0xE7 / 255, alpha: 1)
    private static let darkSurface = NSColor(srgbRed: 0x1E / 255, green: 0x22 / 255, blue: 0x24 / 255, alpha: 1)
    private static let lightInk = NSColor(srgbRed: 0x22 / 255, green: 0x25 / 255, blue: 0x27 / 255, alpha: 1)
    private static let darkInk = NSColor(srgbRed: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF6 / 255, alpha: 1)

    /// Right-aligned like the board: 12 pt edge, clock, 14 pt gap, then the item (6 pt inside its pill), icon + 5 pt + title.
    nonisolated struct ItemLayout: Equatable, Sendable {
        static let edge: CGFloat = 12, gap: CGFloat = 14, itemInset: CGFloat = 6, iconGap: CGFloat = 5
        let clockX: CGFloat
        let titleX: CGFloat
        let iconX: CGFloat

        init(iconWidth: CGFloat, titleWidth: CGFloat, clockWidth: CGFloat, stripWidth: CGFloat) {
            clockX = stripWidth - Self.edge - clockWidth
            let itemRight = clockX - Self.gap - Self.itemInset
            titleX = itemRight - titleWidth
            let inner = iconWidth > 0 && titleWidth > 0 ? Self.iconGap : 0
            iconX = titleX - inner - iconWidth
        }
    }

    /// The icon is always a coloured image here (never a template): this bitmap is drawn outside the menu bar,
    /// where no system tint would be applied to a template.
    private static func icon(for output: RoomMenuBarOutput, ink: NSColor) -> NSImage? {
        let color = tintColor(output.tint) ?? ink
        switch output.icon {
        case .none:
            return nil
        case .mark:
            return RoomPocketMark.image(fill: output.pocketFill, pointSize: iconPoints, tint: color)
        case .symbol:
            let image = NSImage(systemSymbolName: output.symbolName, accessibilityDescription: "Room")?
                .withSymbolConfiguration(.init(paletteColors: [resolved(color)]))
            image?.size = NSSize(width: iconPoints, height: iconPoints)
            return image
        }
    }
}
