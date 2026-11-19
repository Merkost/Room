import AppKit
import SwiftUI
import Testing
@testable import RoomApp

@MainActor
struct RoomTokensContrastTests {
    @Test(arguments: [false, true])
    func tokenPairsMeetContrastRequirements(dark: Bool) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        let canvas = try rgb(RoomTokens.Surface.canvas, appearance)
        let group = try rgb(RoomTokens.Surface.group, appearance)
        for ink in [RoomTokens.Ink.graphite, RoomTokens.Ink.secondary] {
            let foreground = try rgb(ink, appearance)
            #expect(contrast(foreground, canvas) >= 4.5)
            #expect(contrast(foreground, group) >= 4.5)
        }
        for accent in RoomTokens.Accent.allCases {
            #expect(contrast(try rgb(accent.text, appearance), canvas) >= 4.5, "\(accent) text")
            #expect(contrast([1, 1, 1], try rgb(accent.fill, appearance)) >= 4.5, "\(accent) filled button")
        }
        for status in [RoomTokens.Status.normal, RoomTokens.Status.elevated, RoomTokens.Status.critical] {
            #expect(contrast(try rgb(status, appearance), canvas) >= 4.5)
        }
        for kind in RoomTokens.Kind.allCases {
            let tile = try rgb(kind.fill, appearance)
            #expect(contrast(try rgb(kind.mark, appearance), canvas) >= 3, "\(kind) mark")
            #expect(contrast(try rgb(RoomTokens.Kind.tileInk, appearance), tile) >= 4.5, "\(kind) tile label")
            #expect(contrast(try rgb(RoomTokens.Kind.tileInk2, appearance), tile) >= 4.5, "\(kind) tile detail")
        }
        #expect(contrast(try rgb(RoomTokens.Surface.used, appearance), try rgb(RoomTokens.Surface.track, appearance)) >= 3)
        let ring = try rgb(RoomTokens.Ink.secondary, appearance)
        let blendedRing = zip(ring, canvas).map { $0 * 0.8 + $1 * 0.2 }
        #expect(contrast(blendedRing, canvas) >= 3)
    }

    private func rgb(_ color: Color, _ appearance: NSAppearance) throws -> [Double] {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        let srgb = try #require(resolved)
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map(Double.init)
    }

    private func contrast(_ a: [Double], _ b: [Double]) -> Double {
        let luminances: [Double] = [a, b].map { channels in
            zip(channels, [0.2126, 0.7152, 0.0722]).map { value, weight in
                let linear = value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                return linear * weight
            }.reduce(0, +)
        }
        return (max(luminances[0], luminances[1]) + 0.05) / (min(luminances[0], luminances[1]) + 0.05)
    }
}
