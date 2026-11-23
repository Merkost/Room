import AppKit
import SwiftUI
import Testing
@testable import RoomApp

/// DS-5: Increase Contrast uses the tokens' high-contrast steps, thicker plan walls and solid rings.
@MainActor
struct RoomIncreaseContrastTests {
    @Test func wallsThickenAndRingsSolid() {
        #expect(RoomContrast.planWall(.standard) == RoomTokens.OverviewPlan.wall)
        #expect(RoomContrast.planWall(.increased) == 2)
        #expect(RoomContrast.planWall(.increased) > RoomContrast.planWall(.standard))
        #expect(RoomContrast.ringOpacity(.standard) == RoomTokens.Dots.freeRingOpacity)
        #expect(RoomContrast.ringOpacity(.increased) == 1)
    }

    @Test func systemSettingSelectsHighContrastValues() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let light = try #require(NSAppearance(named: .aqua))
        #expect(RoomContrast.appearance(of: dark, systemIncreasesContrast: false) == .dark)
        #expect(RoomContrast.appearance(of: dark, systemIncreasesContrast: true) == .darkHC)
        #expect(RoomContrast.appearance(of: light, systemIncreasesContrast: false) == .light)
        #expect(RoomContrast.appearance(of: light, systemIncreasesContrast: true) == .lightHC)
        // The HC steps are stronger for text and lines.
        #expect(RoomDS.Product.ink2.value(.lightHC) != RoomDS.Product.ink2.value(.light))
        #expect(RoomDS.Product.line.value(.darkHC).alpha > RoomDS.Product.line.value(.dark).alpha)
    }
}
