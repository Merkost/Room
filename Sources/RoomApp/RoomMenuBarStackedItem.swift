import AppKit

/// One stateless drawing path for the status item and the Settings preview.
/// The image stays dynamic until it is drawn, so each menu bar resolves its own ink.
@MainActor
enum RoomMenuBarStackedItem {
    nonisolated struct LineFrames: Equatable, Sendable {
        let symbol: CGRect
        let figure: CGRect
    }

    nonisolated struct Frames: Equatable, Sendable {
        let size: CGSize
        let textBlock: CGRect
        let pocket: CGRect?
        let lines: [LineFrames]
    }

    static func frames(for output: RoomMenuBarOutput, height: CGFloat = 22) -> Frames {
        let lines = output.stackedLines ?? []
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        let textSizes = lines.map { NSAttributedString(string: $0.text, attributes: [.font: font]).size() }
        let figureWidth = ceil(textSizes.map(\.width).max() ?? 0)
        let hasPocket = output.icon != .none
        let blockX: CGFloat = hasPocket ? 16 + 5 : 0
        let block = CGRect(x: blockX, y: (height - 22) / 2, width: 9 + 3 + figureWidth, height: 22)
        let lineFrames = textSizes.enumerated().map { index, size in
            let centre = height / 2 + (index == 0 ? 5.5 : -5.5)
            return LineFrames(
                symbol: CGRect(x: block.minX, y: centre - 4.5, width: 9, height: 9),
                figure: CGRect(x: block.maxX - size.width, y: centre - size.height / 2,
                    width: size.width, height: size.height))
        }
        return Frames(size: CGSize(width: block.maxX, height: height), textBlock: block,
            pocket: hasPocket ? CGRect(x: 0, y: (height - 16) / 2, width: 16, height: 16) : nil,
            lines: lineFrames)
    }

    static func image(for output: RoomMenuBarOutput, pocketFill: Double? = nil, height: CGFloat = 22) -> NSImage {
        let geometry = frames(for: output, height: height)
        let lines = output.stackedLines ?? []
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        let fill = pocketFill ?? output.pocketFill
        let pocketTint = tintColor(output.tint)
        let image = NSImage(size: geometry.size, flipped: false) { _ in
            NSAppearance.currentDrawing().performAsCurrentDrawingAppearance {
                // Resolve inside the handler; creating one image must not bind it to
                // whichever appearance happened to be current at that moment.
                let ink = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
                let markColor = (pocketTint ?? ink).usingColorSpace(.sRGB) ?? ink
                if let pocket = geometry.pocket {
                    RoomPocketMark.image(fill: fill, pointSize: 16, tint: markColor).draw(in: pocket)
                }
                for (line, frames) in zip(lines, geometry.lines) {
                    if let symbol = NSImage(systemSymbolName: line.symbolName, accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(pointSize: 9, weight: .medium))?
                        .withSymbolConfiguration(.init(paletteColors: [ink])) {
                        symbol.isTemplate = false
                        let scale = min(frames.symbol.width / symbol.size.width, frames.symbol.height / symbol.size.height)
                        let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                        symbol.draw(in: CGRect(x: frames.symbol.minX, y: frames.symbol.midY - size.height / 2,
                            width: size.width, height: size.height))
                    }
                    NSAttributedString(string: line.text, attributes: [.font: font, .foregroundColor: ink])
                        .draw(at: frames.figure.origin)
                }
            }
            return true
        }
        image.isTemplate = false
        // A cached non-template bitmap would keep the ink of the first menu bar
        // that drew it. Draw directly so every appearance runs the handler.
        image.cacheMode = .never
        image.accessibilityDescription = output.accessibilityValue
        return image
    }

    private static func tintColor(_ tint: RoomMenuBarTint) -> NSColor? {
        switch tint {
        case .none: nil
        case .normal: RoomTokens.Status.normalAppKit
        case .elevated: RoomTokens.Status.elevatedAppKit
        case .critical: RoomTokens.Status.criticalAppKit
        }
    }
}
