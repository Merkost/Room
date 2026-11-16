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

    @Test(.enabled("NSImage cannot load Resources/RoomMark.svg on this system") {
        await RoomPocketMarkTests.canLoadSVG()
    })
    func hollowMarkMatchesTheSVG() throws {
        let image = try #require(NSImage(contentsOf: Self.svgURL))
        image.size = NSSize(width: 64, height: 64)
        // The template uses the board's 8 8 48 48 viewBox, cropping the
        // resource's 0 0 64 64 canvas without changing its geometry.
        let reference = try alpha(image: image, source: NSRect(x: 8, y: 8, width: 48, height: 48))
        let hollow = try alpha(fill: 0)
        let differences = zip(reference.joined(), hollow.joined()).map { abs($0 - $1) }
        // AppKit's SVG and Core Graphics paths may antialias boundary pixels
        // differently; compare their alpha coverage within one percent overall.
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

    private func alpha(image: NSImage, source: NSRect = .zero) throws -> [[Double]] {
        let pixels = 32
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
