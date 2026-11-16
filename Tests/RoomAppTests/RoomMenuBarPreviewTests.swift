import AppKit
import Testing
@testable import RoomApp

@Suite("Menu bar bitmap previews") @MainActor
struct RoomMenuBarPreviewTests {
    @Test(arguments: RoomMenuBarValueMode.allCases)
    func previewUsesTheRealTitleAndIcon(_ value: RoomMenuBarValueMode) {
        let input = RoomMenuBarInput(value: value, icon: .symbol,
            memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 32_000_000_000, pressure: .normal,
            diskFreeBytes: 312_000_000_000, goalBytes: 50_000_000_000)
        let preview = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes, appearance: .aqua)
        let expected = RoomMenuBarPresentation.make(input, format: .fixtureGigabytes)
        #expect(preview.output == expected)
        #expect(preview.output.title == expected.title && preview.output.icon == expected.icon)
    }

    @Test func previewReturnsAnEager22PointBitmapStrip() throws {
        let preview = RoomMenuBarPreview.make(input: criticalInput, format: .fixtureGigabytes, appearance: .aqua, width: 280)
        #expect(preview.image.size == NSSize(width: 280, height: 22))
        #expect(!preview.image.isTemplate)
        #expect(preview.image.representations.count == 1)
        let bitmap = try #require(preview.image.representations.first as? NSBitmapImageRep)
        #expect(bitmap.size == preview.image.size)
        #expect(bitmap.pixelsWide == 560 && bitmap.pixelsHigh == 44)
        #expect(bitmap.bitmapData != nil)
    }

    @Test func eachAppearanceBakesItsOwnStatusTintIntoThePixels() throws {
        let light = RoomMenuBarPreview.make(input: criticalInput, format: .fixtureGigabytes, appearance: .aqua)
        let dark = RoomMenuBarPreview.make(input: criticalInput, format: .fixtureGigabytes, appearance: .darkAqua)
        let lightBitmap = try #require(light.image.representations.first as? NSBitmapImageRep)
        let darkBitmap = try #require(dark.image.representations.first as? NSBitmapImageRep)
        // Value None centres the full critical pocket. Sample its solid centre,
        // rather than merely proving that the strip backgrounds differ.
        let lightTint = try #require(lightBitmap.colorAt(x: lightBitmap.pixelsWide / 2, y: lightBitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        let darkTint = try #require(darkBitmap.colorAt(x: darkBitmap.pixelsWide / 2, y: darkBitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        #expect(light.output.tint == .critical && dark.output.tint == .critical)
        #expect(abs(lightTint.redComponent - darkTint.redComponent) > 0.1)
        #expect(abs(lightTint.greenComponent - darkTint.greenComponent) > 0.1)
        #expect(lightTint.alphaComponent > 0.99 && darkTint.alphaComponent > 0.99)
        let before = try bytes(lightBitmap)
        let opposite = try #require(NSAppearance(named: .darkAqua))
        opposite.performAsCurrentDrawingAppearance { light.image.recache() }
        #expect(try bytes(lightBitmap) == before)
    }

    @Test func untintedIconsUseReadableInkInBothAppearances() throws {
        let input = RoomMenuBarInput(value: .none, icon: .mark,
            memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 32_000_000_000, pressure: .normal,
            diskFreeBytes: 312_000_000_000, goalBytes: 50_000_000_000)
        let light = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes, appearance: .aqua)
        let dark = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes, appearance: .darkAqua)
        #expect(light.output.tint == .none && dark.output.tint == .none)
        let lightBitmap = try #require(light.image.representations.first as? NSBitmapImageRep)
        let darkBitmap = try #require(dark.image.representations.first as? NSBitmapImageRep)
        #expect(try bytes(lightBitmap) != bytes(darkBitmap))
        let pocket = try #require(darkBitmap.colorAt(x: darkBitmap.pixelsWide / 2, y: darkBitmap.pixelsHigh / 2))
        #expect(pocket.alphaComponent > 0.99)
    }

    private var criticalInput: RoomMenuBarInput {
        RoomMenuBarInput(value: .none, icon: .mark,
            memoryUsedBytes: 30_100_000_000, memoryTotalBytes: 32_000_000_000, pressure: .critical,
            diskFreeBytes: 312_000_000_000, goalBytes: 50_000_000_000)
    }

    private func bytes(_ bitmap: NSBitmapImageRep) throws -> Data {
        let pointer = try #require(bitmap.bitmapData)
        return Data(bytes: pointer, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}
