import AppKit
import Testing
@testable import RoomApp

@Suite("Pocket mark rasterisation") @MainActor
struct RoomPocketMarkTests {
    @Test func fillGrowsTheOpaqueMark() throws {
        let hollow = try alpha(fill: 0)
        let half = try alpha(fill: 0.5)
        let full = try alpha(fill: 1)
        let hollowOpaque = count(hollow) { $0 > 0.96 }
        let halfOpaque = count(half) { $0 > 0.96 }
        let fullOpaque = count(full) { $0 > 0.96 }
        #expect(hollowOpaque < halfOpaque && halfOpaque < fullOpaque)
    }

    @Test func fullPocketHasNoPartlyTransparentCentrePixels() throws {
        let full = try alpha(fill: 1)
        #expect(centrePartial(full) == 0)
    }

    @Test func fullPocketCoversTheWholeBody() throws {
        let full = try alpha(fill: 1)
        #expect(count(full) { $0 > 0.96 } > 620)
    }

    @Test func hollowMarkHasThePocketCutOut() throws {
        let hollow = try alpha(fill: 0)
        #expect(count(hollow) { $0 > 0.96 } < 400)
    }

    @Test func halfPocketHasACleanFillLine() throws {
        let half = try alpha(fill: 0.5)
        #expect(centrePartial(half) <= 4)
    }

    @Test func markStaysInsideItsBoxAndIsATemplate() throws {
        let full = try alpha(fill: 1)
        #expect(RoomPocketMark.image(fill: 0).isTemplate
            && full[0].allSatisfy { $0 < 0.05 }
            && full[31].allSatisfy { $0 < 0.05 })
    }

    @Test func tintedMarkIsAColouredNonTemplateImage() throws {
        // macOS ignores contentTintColor on a status item's template image, so the colour must be drawn into the image.
        let tint = NSColor(srgbRed: 0xC4 / 255, green: 0x24 / 255, blue: 0x2A / 255, alpha: 1)
        let image = RoomPocketMark.image(fill: 1, pointSize: 16, tint: tint)
        #expect(!image.isTemplate)
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32), from: .zero, operation: .sourceOver, fraction: 1)
        let centre = try #require(representation.colorAt(x: 16, y: 16)?.usingColorSpace(.sRGB))
        #expect(abs(centre.redComponent - 0xC4 / 255) < 0.02
            && abs(centre.greenComponent - 0x24 / 255) < 0.02
            && abs(centre.blueComponent - 0x2A / 255) < 0.02
            && centre.alphaComponent > 0.99)
        #expect(RoomPocketMark.image(fill: 1).isTemplate)
    }

    @Test(.enabled("NSImage cannot load Resources/RoomMark.svg on this system") {
        await RoomPocketMarkTests.canLoadSVG()
    })
    func hollowMarkMatchesTheSVG() throws {
        // AppKit rasterises the SVG at a lower fidelity than Core Graphics at small sizes
        // (about 4.4% mean alpha difference at 32 px, 0.6% at 256 px, converging), so the
        // geometry is compared at 256 px where antialiasing no longer dominates.
        let pixels = 256
        let image = try #require(NSImage(contentsOf: Self.svgURL))
        let canvas = Double(pixels) * 64 / 48
        image.size = NSSize(width: canvas, height: canvas)
        // The template uses the board's 8 8 48 48 viewBox, cropping the
        // resource's 0 0 64 64 canvas without changing its geometry.
        let unit = canvas / 64
        let reference = try alpha(image: image, pixels: pixels,
            source: NSRect(x: 8 * unit, y: 8 * unit, width: 48 * unit, height: 48 * unit))
        let hollow = try alpha(image: RoomPocketMark.image(fill: 0, pointSize: 16), pixels: pixels)
        let differences = zip(reference.joined(), hollow.joined()).map { abs($0 - $1) }
        #expect(differences.reduce(0, +) / Double(differences.count) <= 0.01)
    }

    private static var svgURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/RoomMark.svg")
    }

    private static func canLoadSVG() -> Bool {
        NSImage(contentsOf: svgURL)?.isValid == true
    }

    private func alpha(fill: Double) throws -> [[Double]] {
        try alpha(image: RoomPocketMark.image(fill: fill, pointSize: 16))
    }

    private func alpha(image: NSImage, pixels: Int = 32, source: NSRect = .zero) throws -> [[Double]] {
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: source, operation: .sourceOver, fraction: 1)
        return (0..<pixels).map { y in
            (0..<pixels).map { x in
                Double(representation.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
    }

    private func count(_ grid: [[Double]], where predicate: (Double) -> Bool) -> Int {
        grid.joined().filter(predicate).count
    }

    private func centrePartial(_ grid: [[Double]]) -> Int {
        var result = 0
        for y in 8..<24 {
            for x in 8..<24 where grid[y][x] > 0.04 && grid[y][x] < 0.96 {
                result += 1
            }
        }
        return result
    }
}
