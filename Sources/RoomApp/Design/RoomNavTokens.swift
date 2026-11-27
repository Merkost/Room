import SwiftUI

// Room 1.2 navigation and screen hierarchy (nav-v3 mockup). Every literal the redesign needs lives here.
extension RoomTokens {
    enum Nav {
        // Column: a floating glass panel inset from the window edge (mockup `.side`)
        static let labelledWidth: CGFloat = 256
        static let railWidth: CGFloat = 62
        static let columnPadding: CGFloat = 8
        static let panelMargin: CGFloat = 8
        static let panelRadius: CGFloat = 16
        static let panelTop: CGFloat = 12
        static let panelBottom: CGFloat = 10
        static let panelShadowRadius: CGFloat = 12
        static let panelShadowY: CGFloat = 8
        /// The traffic-light row at the top of the panel (lights drawn by the system, the fold button on the right).
        static let lightsRow: CGFloat = 30
        static let lightsBottom: CGFloat = 14
        static let foldSize: CGFloat = 26
        static let foldRadius: CGFloat = 8
        /// Lines the fold button up with the system traffic lights' centre.
        static let foldLift: CGFloat = -5
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
        static let goBottom: CGFloat = 12
        static let railGroupGap: CGFloat = 10
        // Rail peek
        static let peekDelay: Duration = .milliseconds(350)
        static let peekWarm: TimeInterval = 0.6
        static let peekRadius: CGFloat = 12
        static let peekGap: CGFloat = 4
        // Row timing (dwell times, not motion)
        static let settle: Duration = .seconds(4)
        static let shadowRadius: CGFloat = 4
        static let shadowY: CGFloat = 2
    }

    /// The floating dock and the top bar's icons.
    enum Dock {
        static let margin: CGFloat = 12
        static let padding: CGFloat = 7
        static let radius: CGFloat = 24
        static let itemWidth: CGFloat = 82
        static let itemHeight: CGFloat = 64
        static let itemRadius: CGFloat = 17
        static let itemGap: CGFloat = 2
        static let dividerHeight: CGFloat = 36
        static let figureHeight: CGFloat = 15
        static let hoverLift: CGFloat = 3
        static let sideSize: CGFloat = 36
        static let mainWidth: CGFloat = 196
        /// The label's width inside the filled capsule's padding.
        static let mainLabelWidth: CGFloat = 156
        static let barIcon: CGFloat = 28
        static let title = Font.system(size: 11.5, weight: .medium)
        static let titleSelected = Font.system(size: 11.5, weight: .semibold)
        /// What screens leave free at the bottom so nothing hides behind the dock.
        static let reserve: CGFloat = margin + padding * 2 + itemHeight + 6
        /// Clears the window's close, minimise and zoom buttons in the top bar.
        static let trafficLights: CGFloat = 78
    }

    /// The screen hierarchy: one serif headline (number first), one supporting line, the evidence, a quiet note and
    /// at most one filled button.
    enum Screen2 {
        static let headline = Font.custom(RoomDS.displayFamilyName, fixedSize: 62).weight(.medium)
        static let headlineCompact = Font.custom(RoomDS.displayFamilyName, fixedSize: 42).weight(.medium)
        static let headlineTracking: CGFloat = -1.55
        static let supporting = Font.system(size: 15, weight: .regular)
        static let headlineTop: CGFloat = 26
        static let supportingGap: CGFloat = 3
        static let evidenceGap: CGFloat = 32
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
        /// The shortest the Disk Map may get when notices and chips share a small window with it.
        static let mapMinHeight: CGFloat = 140
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
        static let toastBottom: CGFloat = Dock.reserve + 6
        static let toastHold: Duration = .seconds(6)
        static let sheetWidth: CGFloat = 420
        static let sheetRadius: CGFloat = 22
        static let ctaMinWidth: CGFloat = 108
        static let sheetPad: CGFloat = 24
        static let sheetPadBottom: CGFloat = 18
        static let sheetRow: CGFloat = 30
        /// Room under a review's list for its "before you move" lines.
        static let sheetNotes: CGFloat = 76
        static let sheetTop: CGFloat = 104
        static let sheetTitle = Font.custom(RoomDS.displayFamilyName, fixedSize: 26).weight(.medium)
        static let commandWidth: CGFloat = 440
        static let commandRadius: CGFloat = 18
        static let commandTop: CGFloat = 92
        static let commandField = Font.system(size: 17, weight: .regular)
        static let commandRow: CGFloat = 36
        static let commandListMax: CGFloat = 300
        static let scrim = 0.16
        static let scrimDark = 0.4
        // The pane (mockup `.pane`): bar, then the headline 34 below it
        static let switchWidth: CGFloat = 36
        static let switchHeight: CGFloat = 22
        static let paneTop: CGFloat = 9
        static let paneLeading: CGFloat = 30
        static let paneTrailing: CGFloat = 44
        static let paneBottom: CGFloat = 36
        static let barHeight: CGFloat = 34
        static let barTitle = Font.system(size: 14, weight: .semibold)
        static let chipFont = Font.system(size: 12, weight: .regular).monospacedDigit()
        static let chipDot: CGFloat = 6
        static let chipPadH: CGFloat = 11
        static let chipPadV: CGFloat = 5
        // Content arrival on a screen change: 8 pt rise, 3 pt blur, 300 ms ease-out-quint, 30 ms apart, 18 at most
        static let enterRise: CGFloat = 8
        static let enterBlur: CGFloat = 3
        nonisolated static let enterStep: TimeInterval = 0.03
        nonisolated static let enterCap = 18
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
    /// Sidebar labels and values fading as the rail folds (mockup `transition: opacity 160ms`).
    static let labels = Animation.easeOut(duration: 0.16)
    /// The mockup's `--eo` curve, cubic-bezier(.23, 1, .32, 1): press feedback, ticks, content arrival.
    nonisolated static let easeOutQuint = UnitCurve.bezier(startControlPoint: .init(x: 0.23, y: 1),
                                                         endControlPoint: .init(x: 0.32, y: 1))
    static func eo(_ seconds: TimeInterval) -> Animation { .timingCurve(easeOutQuint, duration: seconds) }
    /// Content arrival on a screen change (mockup `enter()`): 300 ms on `--eo`.
    static let enter = eo(0.3)
    /// A number that changes in place: a short blur (mockup `say()`), 200 ms on `--eo`.
    static let say = eo(0.2)
    /// The headline swap (mockup `paint()`): 180 ms on `--eo`.
    static let headlineSwap = eo(0.18)
    /// Peek and command bar glass arriving: 220 / 280 ms UI spring, opacity 140 / 160 ms.
    static let peek = Animation.spring(response: 0.22, dampingFraction: 1)
    static let glass = Animation.spring(response: 0.28, dampingFraction: 1)
    static let peekOut = Animation.easeOut(duration: 0.14)
    static let glassFade = Animation.easeOut(duration: 0.16)
    /// The scrim behind the command bar and review sheet: 200 ms.
    static let scrim = Animation.easeOut(duration: 0.2)
    /// The Disk Map zoom (mockup `zoom()`): 300 ms on `--eo`.
    static let zoom = eo(0.3)
    /// Press feedback: 100 ms on `--eo`.
    static let press = eo(0.1)
    /// Hover washes: 120 ms.
    static let hover = Animation.easeOut(duration: 0.12)
}

extension RoomTokens.Surface {
    /// The sidebar panel glass (mockup `--glass`): white 62 % in light, a raised graphite in dark.
    static let glass = Color.room(RoomDS.Swatch("color.product.glass",
        light: .init(0xFFFFFF, 0.62), dark: .init(0x282B2E, 0.72),
        lightHC: .init(0xFFFFFF, 0.9), darkHC: .init(0x282B2E, 0.95)), name: "room.glass")
    /// The glass top highlight (mockup `--glass-edge`).
    static let glassEdge = Color.room(RoomDS.Swatch("color.product.glassEdge",
        light: .init(0xFFFFFF, 0.9), dark: .init(0xFFFFFF, 0.10),
        lightHC: .init(0xFFFFFF, 1), darkHC: .init(0xFFFFFF, 0.2)), name: "room.glass.edge")
    static let panelShadow = Color.room(RoomDS.Swatch("color.product.panelShadow",
        light: .init(0x000000, 0.12), dark: .init(0x000000, 0.35),
        lightHC: .init(0x000000, 0.2), darkHC: .init(0x000000, 0.45)), name: "room.panel.shadow")
    /// Stand-in icon tiles: the glyph, the hairline and the drop.
    static let onTile = Color.room(light: 0xFFFFFF, dark: 0xFFFFFF, name: "room.tile.on")
    static let tileEdge = Color.room(light: 0x000000, dark: 0x000000, alphaLight: 0.14, alphaDark: 0.3, name: "room.tile.edge")
    static let tileShadow = Color.room(light: 0x000000, dark: 0x000000, alphaLight: 0.12, alphaDark: 0.3, name: "room.tile.shadow")
    /// Sheets, the command bar and the toast (mockup `.pal`, `.sheet`, `.toast`).
    static let sheetGlass = Color.room(RoomDS.Swatch("color.product.sheetGlass",
        light: .init(0xFAFBFC, 0.97), dark: .init(0x26292C, 0.97),
        lightHC: .init(0xFFFFFF, 1), darkHC: .init(0x26292C, 1)), name: "room.sheet.glass")
    static let toastGlass = Color.room(RoomDS.Swatch("color.product.toastGlass",
        light: .init(0xFFFFFF, 0.92), dark: .init(0x34383B, 0.94),
        lightHC: .init(0xFFFFFF, 1), darkHC: .init(0x34383B, 1)), name: "room.toast.glass")
}
