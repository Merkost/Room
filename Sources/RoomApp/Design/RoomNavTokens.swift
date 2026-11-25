import SwiftUI

// Room 1.2 navigation and screen hierarchy (nav-v3 mockup). Every literal the redesign needs lives here.
extension RoomTokens {
    enum Nav {
        // Column
        static let labelledWidth: CGFloat = 248
        static let railWidth: CGFloat = 62
        static let columnPadding: CGFloat = 8
        // Rows
        static let rowHeight: CGFloat = 38
        static let rowGap: CGFloat = 2
        static let rowInsetLeading: CGFloat = 5
        static let rowInsetTrailing: CGFloat = 8
        static let rowColumnGap: CGFloat = 10
        static let tile: CGFloat = 28
        static let tileRadius: CGFloat = 9
        static let glyph: CGFloat = 18
        static let glyphStroke: CGFloat = 1.4
        static let ringInset: CGFloat = 1
        static let ringRadius: CGFloat = 8.5
        static let ringStroke: CGFloat = 2
        static let checkStroke: CGFloat = 1.8
        static let pillRadius: CGFloat = 11
        static let unseenDot: CGFloat = 8
        static let label = Font.system(size: 13.5, weight: .medium)
        static let labelSelected = Font.system(size: 13.5, weight: .semibold)
        static let labelQuiet = Font.system(size: 13.5, weight: .regular)
        static let value = Font.system(size: 12, weight: .regular).monospacedDigit()
        static let valueUnseen = Font.system(size: 12, weight: .semibold).monospacedDigit()
        static let sentence = Font.system(size: 11.5, weight: .regular).monospacedDigit()
        static let group = Font.system(size: 11.5, weight: .regular)
        static let groupTop: CGFloat = 10
        static let groupBottom: CGFloat = 5
        // Developer rooms under the row
        static let kidHeight: CGFloat = 27
        static let kidLeading: CGFloat = 43
        static let kidDot: CGFloat = 5
        static let kid = Font.system(size: 12.5, weight: .regular)
        static let kidSelected = Font.system(size: 12.5, weight: .semibold)
        static let kidStagger: TimeInterval = 0.028
        // Counted dots
        static let dot: CGFloat = 5
        static let dotGap: CGFloat = 3
        nonisolated static let dotMax = 12
        static let dotNowScale: CGFloat = 1.35
        // Memory sparkline
        static let sparkSize = CGSize(width: 46, height: 16)
        nonisolated static let sparkSamples = 14
        static let sparkStroke: CGFloat = 1.3
        static let sparkDot: CGFloat = 4
        // Footer nameplate
        static let plateName = Font.custom(RoomDS.displayFamilyName, fixedSize: 15).weight(.medium)
        static let plateLine = Font.system(size: 11.5, weight: .regular).monospacedDigit()
        static let meterHeight: CGFloat = 4
        static let meterGap: CGFloat = 2
        // Go to field
        static let goHeight: CGFloat = 30
        static let goRadius: CGFloat = 9
        static let goFont = Font.system(size: 12.5, weight: .regular)
        // Rail peek
        static let peekDelay: Duration = .milliseconds(350)
        static let peekWarm: TimeInterval = 0.6
        static let peekRadius: CGFloat = 12
        // Row timing (dwell times, not motion)
        static let settle: Duration = .seconds(4)
        static let shadowRadius: CGFloat = 4
        static let shadowY: CGFloat = 2
    }

    /// The screen hierarchy: one serif headline (number first), one supporting line, the evidence, a quiet note and
    /// at most one filled button.
    enum Screen2 {
        static let headline = Font.custom(RoomDS.displayFamilyName, fixedSize: 56).weight(.medium)
        static let headlineCompact = Font.custom(RoomDS.displayFamilyName, fixedSize: 42).weight(.medium)
        static let headlineTracking: CGFloat = -1.4
        static let supporting = Font.system(size: 15, weight: .regular)
        static let headlineTop: CGFloat = 18
        static let supportingGap: CGFloat = 10
        static let evidenceGap: CGFloat = 30
        static let footerGap: CGFloat = 18
        static let listRow: CGFloat = 40
        static let listName = Font.system(size: 13.5, weight: .medium)
        static let listMeta = Font.system(size: 12, weight: .regular)
        static let listValue = Font.system(size: 13, weight: .semibold).monospacedDigit()
        static let listNameColumn: CGFloat = 250
        static let listNameColumnWide: CGFloat = 330
        static let icon: CGFloat = 26
        static let iconSmall: CGFloat = 22
        static let iconRadius: CGFloat = 7.5
        static let tick: CGFloat = 18
        static let tickStroke: CGFloat = 1.8
        static let dotBarPitch: CGFloat = 10
        static let dotBarDot: CGFloat = 6
        static let dotBarMax = 46
        static let groupLabel = Font.system(size: 11.5, weight: .regular)
        static let factLabel = Font.system(size: 12, weight: .regular)
        static let factValue = Font.system(size: 13.5, weight: .medium)
        static let figure = Font.custom(RoomDS.displayFamilyName, fixedSize: 22).weight(.medium)
        static let planHeight: CGFloat = 226
        static let planGap: CGFloat = 6
        static let planRadius: CGFloat = 14
        static let planPad: CGFloat = 12
        static let planDot: CGFloat = 6.6
        static let planPitch: CGFloat = 15
        static let planDotsTop: CGFloat = 56
        static let planMinFreeWidth: CGFloat = 104
        static let planFreeBoost: Double = 26
        static let mapTileRadius: CGFloat = 12
        static let toastHeight: CGFloat = 40
        static let toastBottom: CGFloat = 88
        static let toastHold: Duration = .seconds(6)
        static let sheetWidth: CGFloat = 420
        static let sheetTitle = Font.custom(RoomDS.displayFamilyName, fixedSize: 26).weight(.medium)
        static let commandWidth: CGFloat = 440
        static let commandTop: CGFloat = 92
        static let commandField = Font.system(size: 17, weight: .regular)
        static let commandRow: CGFloat = 36
        static let commandListMax: CGFloat = 300
        static let scrim = 0.16
        static let scrimDark = 0.4
    }
}

extension RoomTokens.Ink {
    /// The quiet third ink (group headings, values at rest). Increase Contrast lifts it to full ink.
    static let tertiary = Color.room(RoomDS.Swatch("color.product.ink3",
        light: .init(0x8A9296, 1), dark: .init(0x71797D, 1),
        lightHC: .init(0x111314, 1), darkHC: .init(0xFFFFFF, 1)), name: "room.ink3")
}

extension RoomTokens.Surface {
    /// The selection pill and the highlighted command row: near-white glass in light, a lift in dark.
    static let pill = Color.room(RoomDS.Swatch("color.product.pill",
        light: .init(0xFFFFFF, 0.95), dark: .init(0xFFFFFF, 0.09),
        lightHC: .init(0xFFFFFF, 1), darkHC: .init(0xFFFFFF, 0.16)), name: "room.pill")
    /// Quiet glyph tiles and the empty part of meters.
    static let tile = Color.room(RoomDS.Swatch("color.product.tile",
        light: .init(0x1F2224, 0.06), dark: .init(0xF3F5F6, 0.07),
        lightHC: .init(0x1F2224, 0.12), darkHC: .init(0xF3F5F6, 0.14)), name: "room.tile")
    static let pillShadow = Color.room(RoomDS.Swatch("color.product.pillShadow",
        light: .init(0x000000, 0.12), dark: .init(0x000000, 0.3),
        lightHC: .init(0x000000, 0.2), darkHC: .init(0x000000, 0.4)), name: "room.pill.shadow")
    static let scrim = Color.room(RoomDS.Swatch("color.product.scrim",
        light: .init(0x14181A, 0.16), dark: .init(0x000000, 0.4),
        lightHC: .init(0x14181A, 0.3), darkHC: .init(0x000000, 0.55)), name: "room.scrim")
}

extension RoomTokens.Motion {
    /// The nav-v3 UI spring: about 260 ms, critically damped (no overshoot).
    static let ui = Animation.spring(response: 0.26, dampingFraction: 1)
    /// The finished check and the counted dots: the only bounce in navigation.
    static let check = Animation.spring(response: 0.3, dampingFraction: 0.6)
    /// Ring fill between progress reports.
    static let ring = Animation.spring(response: 0.42, dampingFraction: 1)
    /// Rooms on the plan and the Disk Map grow and shrink slowly so a move reads as a change, not a jump.
    static let room = Animation.spring(response: 0.7, dampingFraction: 1)
}
