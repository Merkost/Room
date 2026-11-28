import AppKit
import SwiftUI
import Testing
@testable import RoomApp

/// DS-4: RoomTokens reads RoomDS only where the value is identical. This table is the pre-rewire literals; it must never be
/// regenerated from RoomDS, or the test proves nothing. Colours are compared as resolved sRGB in light and dark (Increase
/// Contrast keeps the same pair as before because the rewired helper still takes only the light and dark values).
@MainActor
struct RoomTokensRewireTests {
    private struct Row { let name: String; let color: Color; let light: UInt32; let dark: UInt32; let alphaLight: Double; let alphaDark: Double }
    private static func row(_ name: String, _ color: Color, _ light: UInt32, _ dark: UInt32, _ al: Double = 1, _ ad: Double = 1) -> Row {
        Row(name: name, color: color, light: light, dark: dark, alphaLight: al, alphaDark: ad)
    }

    private static let colours: [Row] = [
        row("Ink.graphite", RoomTokens.Ink.graphite, 0x222527, 0xF3F5F6),
        row("Ink.secondary", RoomTokens.Ink.secondary, 0x5B6266, 0xA3A9AC),
        row("Ink.iconGraphite", RoomTokens.Ink.iconGraphite, 0x222527, 0x222527),
        row("Surface.canvas", RoomTokens.Surface.canvas, 0xF3F5F6, 0x17191A),
        row("Surface.group", RoomTokens.Surface.group, 0xFFFFFF, 0x202325),
        row("Surface.track", RoomTokens.Surface.track, 0xE3E7E9, 0x2C3033),
        row("Surface.used", RoomTokens.Surface.used, 0x4A5257, 0x9AA3A8),
        row("Surface.hover", RoomTokens.Surface.hover, 0x222527, 0xF3F5F6, 0.045, 0.05),
        row("Surface.press", RoomTokens.Surface.press, 0x222527, 0xF3F5F6, 0.09, 0.10),
        row("Surface.line", RoomTokens.Surface.line, 0x222527, 0xF3F5F6, 0.10, 0.09),
        row("Surface.line2", RoomTokens.Surface.line2, 0x222527, 0xF3F5F6, 0.16, 0.16),
        row("Surface.hatch", RoomTokens.Surface.hatch, 0x222527, 0xF3F5F6, 0.16, 0.16),
        row("Accent.teal.fill", RoomTokens.Accent.teal.fill, 0x3D7482, 0x37717F),
        row("Accent.teal.text", RoomTokens.Accent.teal.text, 0x3D7482, 0x7FB5C3),
        row("Accent.teal.wash", RoomTokens.Accent.teal.wash, 0x3D7482, 0x7FB5C3, 0.10, 0.14),
        row("Accent.graphite.fill", RoomTokens.Accent.graphite.fill, 0x3A4146, 0x596167),
        row("Accent.graphite.text", RoomTokens.Accent.graphite.text, 0x3A4146, 0xD2D8DB),
        row("Accent.harbour.fill", RoomTokens.Accent.harbour.fill, 0x3A6491, 0x3A6289),
        row("Accent.harbour.text", RoomTokens.Accent.harbour.text, 0x3A6491, 0x8DB4DD),
        row("Accent.berry.fill", RoomTokens.Accent.berry.fill, 0x8A4766, 0x84476A),
        row("Accent.berry.text", RoomTokens.Accent.berry.text, 0x8A4766, 0xDDA6C0),
        row("Status.normal", RoomTokens.Status.normal, 0x2E7D4F, 0x5CC08A),
        row("Status.elevated", RoomTokens.Status.elevated, 0xA3590A, 0xF0A040),
        row("Status.critical", RoomTokens.Status.critical, 0xC4242A, 0xFF6B66),
        row("Status.elevatedWash", RoomTokens.Status.elevatedWash, 0xA3590A, 0xF0A040, 0.09, 0.12),
        row("Kind.developer.fill", RoomTokens.Kind.developer.fill, 0xA9CBD4, 0x2E5560),
        row("Kind.media.fill", RoomTokens.Kind.media.fill, 0xBACFB2, 0x3C5236),
        row("Kind.documents.fill", RoomTokens.Kind.documents.fill, 0xB9C4DA, 0x38455E),
        row("Kind.apps.fill", RoomTokens.Kind.apps.fill, 0xDCCDA6, 0x58492C),
        row("Kind.archives.fill", RoomTokens.Kind.archives.fill, 0xDDBBA9, 0x5C3F33),
        row("Kind.system.fill", RoomTokens.Kind.system.fill, 0xCBD0D3, 0x3A3F43),
        row("Kind.hidden.fill", RoomTokens.Kind.hidden.fill, 0xCCBCD3, 0x4A3C52),
        row("Kind.developer.mark", RoomTokens.Kind.developer.mark, 0x137A8F, 0x6CBFCC),
        row("Kind.media.mark", RoomTokens.Kind.media.mark, 0x276F1C, 0x85C678),
        row("Kind.documents.mark", RoomTokens.Kind.documents.mark, 0x3A57BA, 0xA9B8F6),
        row("Kind.apps.mark", RoomTokens.Kind.apps.mark, 0xA07800, 0xE6BB45),
        row("Kind.archives.mark", RoomTokens.Kind.archives.mark, 0xB73F2B, 0xE0705A),
        row("Kind.system.mark", RoomTokens.Kind.system.mark, 0x717980, 0x9AA4AA),
        row("Kind.hidden.mark", RoomTokens.Kind.hidden.mark, 0xA75FC1, 0xB489CE),
        row("Kind.tileInk", RoomTokens.Kind.tileInk, 0x222527, 0xF3F5F6),
        row("Kind.tileInk2", RoomTokens.Kind.tileInk2, 0x3E4448, 0xC5CCD0)
    ]

    @Test func coloursResolveToTheirPreRewireValues() throws {
        for (appearanceName, isDark) in [(NSAppearance.Name.aqua, false), (.darkAqua, true)] {
            let appearance = try #require(NSAppearance(named: appearanceName))
            for row in Self.colours {
                var resolved: NSColor?
                appearance.performAsCurrentDrawingAppearance { resolved = NSColor(row.color).usingColorSpace(.sRGB) }
                let c = try #require(resolved, "\(row.name)")
                let want = NSColor(roomHex: isDark ? row.dark : row.light, alpha: isDark ? row.alphaDark : row.alphaLight).usingColorSpace(.sRGB)
                let w = try #require(want)
                #expect(c.redComponent == w.redComponent && c.greenComponent == w.greenComponent && c.blueComponent == w.blueComponent && c.alphaComponent == w.alphaComponent,
                        "\(row.name) \(isDark ? "dark" : "light")")
            }
        }
    }

    @Test func spaceAndRadiusAreUnchanged() {
        #expect(RoomTokens.Space.row == 8)
        #expect(RoomTokens.Space.inner == 12)
        #expect(RoomTokens.Space.group == 16)
        #expect(RoomTokens.Space.breath1 == 24)
        #expect(RoomTokens.Space.breath2 == 40)
        #expect(RoomTokens.Space.breath3 == 64)
        #expect(RoomTokens.Space.breath4 == 96)
        #expect(RoomTokens.Space.measure == 560)
        #expect(RoomTokens.Space.tight == 6)
        #expect(RoomTokens.Radius.tile == 5)
        #expect(RoomTokens.Radius.field == 6)
        #expect(RoomTokens.Radius.row == 8)
        #expect(RoomTokens.Radius.card == 10)
        #expect(RoomTokens.Radius.group == 12)
        #expect(RoomTokens.Radius.popover == 16)
        #expect(RoomTokens.Radius.sheet == 20)
        #expect(RoomTokens.Radius.planRoom == 3)
        #expect(RoomTokens.Radius.plan == 11, "plan stays 11 until the owner approves 10")
    }

    @Test func typographyIsUnchanged() {
        typealias T = RoomTokens.Typography
        #expect(T.hero == Font.system(size: 40, weight: .regular).monospacedDigit())
        #expect(T.figure == Font.system(size: 22, weight: .regular).monospacedDigit())
        #expect(T.title == Font.system(size: 15, weight: .semibold))
        #expect(T.lead == Font.system(size: 15, weight: .regular))
        #expect(T.section == Font.system(size: 13, weight: .semibold))
        #expect(T.body == Font.system(size: 13, weight: .regular))
        #expect(T.caption == Font.system(size: 12, weight: .regular))
        #expect(T.path == Font.system(size: 11.5, weight: .regular, design: .monospaced))
        #expect(T.heroTracking == -0.8)
        #expect(T.unit(for: 40) == Font.system(size: 16, weight: .regular))
        #expect(T.unit(for: 20) == Font.system(size: 14, weight: .regular))
    }

    /// DS-9: the four RoomDS durations, the page spring and the one overshoot; no duplicate timings.
    @Test func motionUsesTheDSDurations() {
        typealias M = RoomTokens.Motion
        #expect(M.quick == Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12))
        #expect(M.standard == Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.20))
        #expect(M.pageResponse == 0.32)
        #expect(M.page == Animation.spring(response: 0.32, dampingFraction: 1))
        #expect(M.success == Animation.spring(response: 0.28, dampingFraction: 0.7))
        #expect(M.count == 0.32)
        #expect(M.stagger == 0.03)
        #expect(M.maxStaggered == 12)
        #expect(M.tooltipDelay == 0.5)
        #expect(M.pressScale == 0.96)
        #expect(M.fadeDuration == 0.15)
        #expect(M.morphDuration == RoomDS.Motion.Duration.page.seconds)
        #expect(M.groupStagger == 0.07)
    }
}
