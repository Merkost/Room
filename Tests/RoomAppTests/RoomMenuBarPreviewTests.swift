import AppKit
import Testing
@testable import RoomApp

@Suite("Menu bar bitmap previews") @MainActor
struct RoomMenuBarPreviewTests {
    @Test func settingsSamplesDisplayTheSpecifiedDecimalFigures() {
        let scenarios = RoomMenuBarPreviewScenarios.inputs(from: RoomMenuBarInput(
            value: .both, icon: .mark, goalBytes: 50_000_000_000))
        let normal = RoomMenuBarPreview.make(input: scenarios.normal,
            format: RoomMenuBarPreview.settingsFormat, appearance: .aqua)
        let elevated = RoomMenuBarPreview.make(input: scenarios.elevated,
            format: RoomMenuBarPreview.settingsFormat, appearance: .darkAqua)
        #expect(normal.output.title == "16.2 GB · 312 GB")
        #expect(elevated.output.title == "24.8 GB · 41 GB")
        #expect(normal.output.accessibilityValue.contains("16.2 GB memory used of 32 GB"))
        #expect(elevated.output.accessibilityValue.contains("24.8 GB memory used of 32 GB"))
    }

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

    @Test func previewReturnsAnEager24PointBitmapStrip() throws {
        let preview = RoomMenuBarPreview.make(input: criticalInput, format: .fixtureGigabytes, appearance: .aqua, width: 280)
        #expect(preview.image.size == NSSize(width: 280, height: 24))
        #expect(!preview.image.isTemplate)
        #expect(preview.image.representations.count == 1)
        let bitmap = try #require(preview.image.representations.first as? NSBitmapImageRep)
        #expect(bitmap.size == preview.image.size)
        #expect(bitmap.pixelsWide == 560 && bitmap.pixelsHigh == 48)
        #expect(bitmap.bitmapData != nil)
    }

    @Test func layoutIsRightAlignedLikeTheBoardStrip() {
        let layout = RoomMenuBarPreview.ItemLayout(iconWidth: 16, titleWidth: 50, clockWidth: 34, stripWidth: 280)
        #expect(layout.clockX + 34 + RoomMenuBarPreview.ItemLayout.edge == 280)
        #expect(layout.titleX + 50 + RoomMenuBarPreview.ItemLayout.itemInset + RoomMenuBarPreview.ItemLayout.gap == layout.clockX)
        #expect(layout.iconX + 16 + RoomMenuBarPreview.ItemLayout.iconGap == layout.titleX)
        let iconOnly = RoomMenuBarPreview.ItemLayout(iconWidth: 16, titleWidth: 0, clockWidth: 34, stripWidth: 280)
        #expect(iconOnly.iconX + 16 + RoomMenuBarPreview.ItemLayout.itemInset + RoomMenuBarPreview.ItemLayout.gap == iconOnly.clockX)
    }

    @Test(arguments: RoomMenuBarIconMode.allCases)
    func stackedFramesUseTheSharedTextBlockAndPocket(_ icon: RoomMenuBarIconMode) throws {
        var input = RoomMenuBarInput(value: .both, icon: icon,
            memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 32_000_000_000, pressure: .normal,
            diskFreeBytes: 312_000_000_000, goalBytes: 50_000_000_000)
        input.layout = .stacked
        let preview = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes, appearance: .aqua, width: 280)
        let frames = RoomMenuBarPreview.frames(for: preview.output, width: 280)
        let geometry = RoomMenuBarStackedItem.frames(for: preview.output, height: 24)
        let text = try #require(frames.title)
        #expect(text.size == geometry.textBlock.size)
        #expect(text.midY == 12)
        #expect(text.maxX + RoomMenuBarPreview.ItemLayout.itemInset + RoomMenuBarPreview.ItemLayout.gap == frames.clock.minX)
        if icon == .none {
            #expect(frames.icon == nil)
        } else {
            let pocket = try #require(frames.icon)
            #expect(pocket.size == CGSize(width: 16, height: 16))
            #expect(pocket.maxX + 5 == text.minX)
            #expect(pocket.midY == text.midY)
            #expect(preview.output.icon == .mark)
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func stackedPreviewDrawsBothLinesWithoutChangingTheStaticLayer(_ appearance: NSAppearance.Name) throws {
        var input = RoomMenuBarInput(value: .both, icon: .mark,
            memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 32_000_000_000, pressure: .normal,
            diskFreeBytes: 312_000_000_000, goalBytes: 50_000_000_000)
        let inlineStatic = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes,
            appearance: appearance, width: 280, layers: .surfaceAndClock)
        input.layout = .stacked
        let stackedStatic = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes,
            appearance: appearance, width: 280, layers: .surfaceAndClock)
        #expect(try bytes(try #require(inlineStatic.image.representations.first as? NSBitmapImageRep))
            == bytes(try #require(stackedStatic.image.representations.first as? NSBitmapImageRep)))
        let item = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes,
            appearance: appearance, width: 280, layers: .itemOnly)
        let bitmap = try #require(item.image.representations.first as? NSBitmapImageRep)
        let text = try #require(RoomMenuBarPreview.frames(for: item.output, width: 280).title)
        func inked(_ rect: CGRect) throws -> Int {
            var count = 0
            for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) {
                for y in Int((24 - rect.maxY) * 2)..<Int((24 - rect.minY) * 2) {
                    if try #require(bitmap.colorAt(x: x, y: y)).alphaComponent > 0.5 { count += 1 }
                }
            }
            return count
        }
        #expect(try inked(CGRect(x: text.minX, y: text.midY, width: text.width, height: text.height / 2)) > 40)
        #expect(try inked(CGRect(x: text.minX, y: text.minY, width: text.width, height: text.height / 2)) > 40)
        #expect(try #require(bitmap.colorAt(x: 2, y: 2)).alphaComponent == 0)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func stripsActuallyDrawTheItemTitleAndClock(_ appearance: NSAppearance.Name) throws {
        let input = RoomMenuBarInput(value: .memory, icon: .symbol,
            memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 32_000_000_000, pressure: .normal,
            diskFreeBytes: 312_000_000_000, goalBytes: 50_000_000_000)
        let preview = RoomMenuBarPreview.make(input: input, format: RoomMenuBarPreview.settingsFormat, appearance: appearance, width: 280)
        let bitmap = try #require(preview.image.representations.first as? NSBitmapImageRep)
        let frames = RoomMenuBarPreview.frames(for: preview.output, width: 280)
        let surface = try #require(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.sRGB))
        func inked(_ rect: CGRect) throws -> Int {
            var count = 0
            for px in Int(rect.minX * 2)..<Int(rect.maxX * 2) {
                for py in Int((24 - rect.maxY) * 2)..<Int((24 - rect.minY) * 2) {
                    let color = try #require(bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB))
                    if abs(color.redComponent - surface.redComponent) > 0.25 { count += 1 }
                }
            }
            return count
        }
        #expect(try inked(frames.clock) > 20)
        #expect(try inked(try #require(frames.title)) > 40)
        #expect(try inked(try #require(frames.icon)) > 20)
    }

    @Test func eachAppearanceBakesItsOwnStatusTintIntoThePixels() throws {
        let light = RoomMenuBarPreview.make(input: criticalInput, format: .fixtureGigabytes, appearance: .aqua, width: 280)
        let dark = RoomMenuBarPreview.make(input: criticalInput, format: .fixtureGigabytes, appearance: .darkAqua, width: 280)
        let lightBitmap = try #require(light.image.representations.first as? NSBitmapImageRep)
        let darkBitmap = try #require(dark.image.representations.first as? NSBitmapImageRep)
        // Value None leaves only the icon: the full critical pocket. Sample its solid centre.
        let lightIcon = try #require(RoomMenuBarPreview.frames(for: light.output, width: 280).icon)
        let darkIcon = try #require(RoomMenuBarPreview.frames(for: dark.output, width: 280).icon)
        let lightTint = try #require(lightBitmap.colorAt(x: Int(lightIcon.midX * 2), y: Int((24 - lightIcon.midY) * 2))?.usingColorSpace(.sRGB))
        let darkTint = try #require(darkBitmap.colorAt(x: Int(darkIcon.midX * 2), y: Int((24 - darkIcon.midY) * 2))?.usingColorSpace(.sRGB))
        #expect(light.output.tint == .critical && dark.output.tint == .critical)
        #expect(abs(lightTint.redComponent - darkTint.redComponent) > 0.1 || abs(lightTint.greenComponent - darkTint.greenComponent) > 0.1)
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
        let light = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes, appearance: .aqua, width: 280)
        let dark = RoomMenuBarPreview.make(input: input, format: .fixtureGigabytes, appearance: .darkAqua, width: 280)
        #expect(light.output.tint == .none && dark.output.tint == .none)
        // The hollow mark's outer ring is solid ink; sample the middle of its left wall (x 1.3 to 3.7 pt).
        func ring(_ preview: RoomMenuBarPreview) throws -> NSColor {
            let bitmap = try #require(preview.image.representations.first as? NSBitmapImageRep)
            let icon = try #require(RoomMenuBarPreview.frames(for: preview.output, width: 280).icon)
            return try #require(bitmap.colorAt(x: Int((icon.minX + 2.5) * 2), y: Int((24 - icon.midY) * 2))?.usingColorSpace(.sRGB))
        }
        let lightInk = try ring(light), darkInk = try ring(dark)
        #expect(lightInk.redComponent < 0.3 && darkInk.redComponent > 0.8)
        #expect(lightInk.alphaComponent > 0.99 && darkInk.alphaComponent > 0.99)
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
