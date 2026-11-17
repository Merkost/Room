import AppKit
import Testing
@testable import RoomApp

@Suite("Stacked menu bar item rasterisation") @MainActor
struct RoomMenuBarStackedItemTests {
    @Test func itemFitsTheStatusBarAndHasOneNonTemplateImage() {
        let output = stackedOutput()
        let image = RoomMenuBarStackedItem.image(for: output)
        let frames = RoomMenuBarStackedItem.frames(for: output)
        #expect(image.size == frames.size)
        #expect(image.size.height <= 22)
        #expect(!image.isTemplate)
        #expect(image.accessibilityDescription == output.accessibilityValue)
        #expect(frames.pocket?.width == 16)
        #expect(frames.textBlock.minX == 21)
        #expect(frames.lines.map { $0.figure.maxX } == [frames.textBlock.maxX, frames.textBlock.maxX])
        #expect(frames.lines.map { $0.symbol.minX } == [frames.textBlock.minX, frames.textBlock.minX])
        #expect(frames.lines.map { $0.symbol.midY } == [frames.size.height / 2 + 5.5, frames.size.height / 2 - 5.5])
        #expect(frames.lines.map { $0.figure.midY } == [frames.size.height / 2 + 5.5, frames.size.height / 2 - 5.5])
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func bothTextLinesAndTheirSymbolsDrawInNeutralInk(_ appearance: NSAppearance.Name) throws {
        let output = stackedOutput()
        let frames = RoomMenuBarStackedItem.frames(for: output)
        let bitmap = try rasterize(RoomMenuBarStackedItem.image(for: output), appearance: appearance)
        let block = frames.textBlock
        let upper = CGRect(x: block.minX, y: block.midY, width: block.width, height: block.height / 2)
        let lower = CGRect(x: block.minX, y: block.minY, width: block.width, height: block.height / 2)
        #expect(try inkedPixels(in: upper, bitmap: bitmap, height: frames.size.height) > 40)
        #expect(try inkedPixels(in: lower, bitmap: bitmap, height: frames.size.height) > 40)
        for line in frames.lines {
            #expect(try inkedPixels(in: line.symbol, bitmap: bitmap, height: frames.size.height) > 5)
            #expect(try inkedPixels(in: line.figure, bitmap: bitmap, height: frames.size.height) > 30)
        }
        // Even at critical pressure, the symbols and figures remain label ink.
        for rect in [upper, lower] {
            let ink = try strongestInk(in: rect, bitmap: bitmap, height: frames.size.height)
            #expect(abs(ink.redComponent - ink.greenComponent) < 0.05)
            #expect(abs(ink.greenComponent - ink.blueComponent) < 0.05)
        }
    }

    @Test func theSameImageResolvesInkAndPocketTintForEachDrawingAppearance() throws {
        let output = stackedOutput()
        let image = RoomMenuBarStackedItem.image(for: output)
        let frames = RoomMenuBarStackedItem.frames(for: output)
        let light = try rasterize(image, appearance: .aqua)
        let dark = try rasterize(image, appearance: .darkAqua)
        let lightInk = try strongestInk(in: frames.textBlock, bitmap: light, height: frames.size.height)
        let darkInk = try strongestInk(in: frames.textBlock, bitmap: dark, height: frames.size.height)
        #expect(lightInk.redComponent < 0.3)
        #expect(darkInk.redComponent > 0.8)

        let pocket = try #require(frames.pocket)
        let lightTint = try color(at: CGPoint(x: pocket.midX, y: pocket.midY), bitmap: light, height: frames.size.height)
        let darkTint = try color(at: CGPoint(x: pocket.midX, y: pocket.midY), bitmap: dark, height: frames.size.height)
        let lightAppearance = try #require(NSAppearance(named: .aqua))
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        var expectedLight = NSColor.clear, expectedDark = NSColor.clear
        lightAppearance.performAsCurrentDrawingAppearance {
            expectedLight = RoomTokens.Status.criticalAppKit.usingColorSpace(.sRGB) ?? .clear
        }
        darkAppearance.performAsCurrentDrawingAppearance {
            expectedDark = RoomTokens.Status.criticalAppKit.usingColorSpace(.sRGB) ?? .clear
        }
        #expect(abs(lightTint.redComponent - expectedLight.redComponent) < 0.03)
        #expect(abs(lightTint.greenComponent - expectedLight.greenComponent) < 0.03)
        #expect(abs(darkTint.redComponent - expectedDark.redComponent) < 0.03)
        #expect(abs(darkTint.greenComponent - expectedDark.greenComponent) < 0.03)
        #expect(lightTint.alphaComponent > 0.99 && darkTint.alphaComponent > 0.99)
    }

    @Test func iconNoneRemovesThePocketAndItsGap() {
        let withPocket = RoomMenuBarStackedItem.frames(for: stackedOutput())
        let withoutPocket = RoomMenuBarStackedItem.frames(for: stackedOutput(icon: .none))
        #expect(withoutPocket.pocket == nil)
        #expect(withoutPocket.textBlock.minX == 0)
        #expect(withPocket.size.width - withoutPocket.size.width == 21)
        #expect(withPocket.textBlock.size == withoutPocket.textBlock.size)
    }

    private func stackedOutput(icon: RoomMenuBarIconMode = .mark) -> RoomMenuBarOutput {
        var input = RoomMenuBarInput(value: .both, icon: icon,
            memoryUsedBytes: 30_100_000_000, memoryTotalBytes: 32_000_000_000, pressure: .critical,
            diskFreeBytes: 312_000_000_000, goalBytes: 50_000_000_000)
        input.layout = .stacked
        return RoomMenuBarPresentation.make(input, format: .fixtureGigabytes)
    }

    private func rasterize(_ image: NSImage, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(image.size.width * 2)), pixelsHigh: Int(ceil(image.size.height * 2)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        let drawingAppearance = try #require(NSAppearance(named: appearance))
        drawingAppearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            image.draw(in: CGRect(x: 0, y: 0, width: image.size.width * 2, height: image.size.height * 2),
                from: .zero, operation: .sourceOver, fraction: 1)
        }
        return bitmap
    }

    private func color(at point: CGPoint, bitmap: NSBitmapImageRep, height: CGFloat) throws -> NSColor {
        try #require(bitmap.colorAt(x: Int(point.x * 2), y: Int((height - point.y) * 2))?.usingColorSpace(.sRGB))
    }

    private func inkedPixels(in rect: CGRect, bitmap: NSBitmapImageRep, height: CGFloat) throws -> Int {
        let visible = rect.intersection(CGRect(x: 0, y: 0, width: CGFloat(bitmap.pixelsWide) / 2, height: height))
        guard !visible.isEmpty else { return 0 }
        var count = 0
        for x in Int(visible.minX * 2)..<Int(visible.maxX * 2) {
            for y in Int((height - visible.maxY) * 2)..<Int((height - visible.minY) * 2) {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if color.alphaComponent > 0.5 { count += 1 }
            }
        }
        return count
    }

    private func strongestInk(in rect: CGRect, bitmap: NSBitmapImageRep, height: CGFloat) throws -> NSColor {
        var strongest = NSColor.clear
        for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) {
            for y in Int((height - rect.maxY) * 2)..<Int((height - rect.minY) * 2) {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.alphaComponent > strongest.alphaComponent { strongest = color }
            }
        }
        #expect(strongest.alphaComponent > 0.7)
        return strongest
    }
}
