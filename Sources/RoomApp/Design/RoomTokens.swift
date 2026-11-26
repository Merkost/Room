// RoomTokens: the only place in RoomApp where fonts, sizes, colours, radii and timings are literals.
// Spec: 02-FOUNDATIONS.md. Typechecked standalone with:
//   swiftc -typecheck -swift-version 6 -default-isolation MainActor -target arm64-apple-macos26.0 RoomTokens.swift
import AppKit
import SwiftUI

// MARK: - Colour helper

extension Color {
    /// A colour with one value for light (aqua) and one for dark (darkAqua) appearance.
    /// Increase Contrast picks the same pair; contrast is already >= 4.5:1 for text roles (15-ACCESSIBILITY.md).
    static func room(light: UInt32, dark: UInt32, alphaLight: Double = 1, alphaDark: Double = 1, name: String) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(roomHex: isDark ? dark : light, alpha: isDark ? alphaDark : alphaLight)
        })
    }
}

extension Color {
    /// A `RoomDS` swatch with all four values: light, dark, and their Increase Contrast steps (DS-5). The colour keeps
    /// its `room.*` name so nothing that caches by name changes.
    static func room(_ swatch: RoomDS.Swatch, name: String) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            swatch.value(RoomContrast.appearance(of: appearance)).nsColor
        })
    }
}

/// Which of the four token values applies. The window's appearance says light or dark; Increase Contrast comes from the
/// appearance when AppKit offers the high-contrast names, else from the system setting (BRAND-DS §13 fallback).
nonisolated enum RoomContrast {
    static func appearance(of nsAppearance: NSAppearance,
                           systemIncreasesContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        -> RoomDS.Appearance {
        let fromAppearance = RoomDS.Swatch.appearance(of: nsAppearance)
        let dark = fromAppearance == .dark || fromAppearance == .darkHC
        let high = fromAppearance == .lightHC || fromAppearance == .darkHC || systemIncreasesContrast
        return RoomDS.Swatch.resolve(dark: dark, highContrast: high)
    }

    /// Plan walls: 1.5 pt, 2 pt under Increase Contrast (spec 15 §4).
    @MainActor static func planWall(_ contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? RoomTokens.OverviewPlan.elevatedWall : RoomTokens.OverviewPlan.wall
    }

    /// Free-space rings: 80 % ink, solid under Increase Contrast.
    @MainActor static func ringOpacity(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 1 : RoomTokens.Dots.freeRingOpacity
    }
}

extension NSColor {
    convenience init(roomHex hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: CGFloat(alpha))
    }
}

enum RoomTokens {

    // MARK: Type ladder 40 / 22 / 15 / 13 / 12 / 11
    enum Typography {
        /// Tier 1: the Overview answer and the one hero figure per screen. Regular weight, tabular.
        static let hero = RoomDS.TypeRole.numberXl.font
        static let heroTracking: CGFloat = -0.8
        /// Sibling figures (Caches found, Kept safe), Memory pressure word next to the pocket.
        static let figure = RoomDS.TypeRole.number.font
        /// Toolbar titles, chapter headings (semibold) and the quiet greeting / goal sentence (regular).
        static let title = RoomDS.TypeRole.h1.font
        static let lead = RoomDS.TypeRole.lead.font
        /// Section headings inside a screen.
        static let section = RoomDS.TypeRole.h2.font
        static let body = RoomDS.TypeRole.body.font
        static let bodyStrong = Font.system(size: 13, weight: .medium)
        static let counter = Font.system(size: 17, weight: .regular).monospacedDigit()
        static let roomGlyph = Font.system(size: 10, weight: .medium)
        static let numeric = Font.system(size: 13, weight: .regular).monospacedDigit()
        static let caption = RoomDS.TypeRole.small.font
        static let sidebarGroup = Font.system(size: 11, weight: .semibold)
        static let navigationLabel = Font.system(size: 12, weight: .medium)
        static let captionNumeric = Font.system(size: 12, weight: .regular).monospacedDigit()
        static let aboutHeading = Font.system(size: 22, weight: .semibold)
        static let emptyHeading = Font.system(size: 30, weight: .semibold)
        static let aboutTagline = Font.system(size: 15, weight: .medium)
        static let madeRoom = Font.system(size: 28, weight: .regular).monospacedDigit()
        /// Functional text floor (DESIGN.md): ticks, key caps, plan labels. Never smaller.
        static let micro = Font.system(size: 11, weight: .regular)
        /// SF Mono only for paths and versions.
        static let path = RoomDS.TypeRole.mono.font
        static let version = Font.system(size: 12, weight: .regular, design: .monospaced)
        /// Unit attached to a figure, on its baseline: 0.4 x figure size, minimum 14 (RoomByteMetric rule).
        static func unit(for figureSize: CGFloat) -> Font { RoomDS.unitFont(for: figureSize) }
        /// Tracking: -0.5 for 40 pt, -0.2 for 22 pt, 0 below.
        static func tracking(for size: CGFloat) -> CGFloat { size >= 30 ? -0.5 : size >= 20 ? -0.2 : 0 }
    }

    enum Screen {
        static let compactBreakpoint: CGFloat = 700
        static let maximumColumnWidth: CGFloat = 1_120
    }

    enum Overview {
        static let greetingLineHeight: CGFloat = 20
        static let answerLineHeight: CGFloat = 44
        static let goalLineHeight: CGFloat = 22
        static let goalSpacing: CGFloat = 10
        static let actionSpacing: CGFloat = 20
        static let actionHeight: CGFloat = 34
    }

    enum OverviewPlan {
        static let dimmedKind = 0.18
        static let quietLabelOpacity = 0.7
        static let categoryWash = 0.55
        static let chartMinimumWidth: CGFloat = 310
        static let chartHeight: CGFloat = 166
        static let compactChartHeight: CGFloat = 134
        static let legendWidth: CGFloat = 192
        static let legendColumnMinimum: CGFloat = 140
        static let legendRowHeight: CGFloat = 22
        static let swatchSize: CGFloat = 8
        static let pad: CGFloat = 5
        static let captionHeight: CGFloat = 14
        static let outerRadius: CGFloat = 10
        static let wall: CGFloat = 1.5
        static let elevatedWall: CGFloat = 2
        static let dashedWall = StrokeStyle(lineWidth: 1, dash: [4, 3])
        static let focusWall: CGFloat = 2
        static let focusOffset: CGFloat = 1
        static let roomGap: CGFloat = 2
        static let labelInset: CGFloat = 8
        static let labelLineHeight: CGFloat = 14
        static let freeLabelHeight: CGFloat = 28
        static let goalInset: CGFloat = 6
        static let minimumGoalWidth: CGFloat = 20
        static let goalLabelSize = CGSize(width: 72, height: 18)
        static let gridPoint: CGFloat = 1
        static let gridPitchFactor: CGFloat = 0.5
        static let freeLabel = Font.system(size: 12, weight: .semibold)
    }

    // MARK: Spacing (pt). Calm is the default density; Compact is v2's spacing.
    enum Space {
        static let tight: CGFloat = 6
        static let row: CGFloat = RoomDS.Space.row
        static let inner: CGFloat = RoomDS.Space.inner
        static let group: CGFloat = RoomDS.Space.group
        /// Breath tokens (board decision 25).
        static let breath1: CGFloat = RoomDS.Space.breath1   // inside a chapter
        static let breath2: CGFloat = RoomDS.Space.breath2   // between groups; Calm gutter
        static let breath3: CGFloat = RoomDS.Space.breath3   // reserved: Settings, onboarding
        static let breath4: CGFloat = RoomDS.Space.breath4   // between chapters
        static let measure: CGFloat = RoomDS.Space.measure  // text measure and plan width (Calm)
    }

    enum Density: String, CaseIterable, Codable, Sendable {
        case calm, compact
        var gutter: CGFloat { self == .calm ? 40 : 24 }
        var topInset: CGFloat { self == .calm ? 24 : 16 }
        var betweenGroups: CGFloat { self == .calm ? 40 : 24 }
        var insideChapter: CGFloat { self == .calm ? 24 : 16 }
        var betweenChapters: CGFloat { self == .calm ? 96 : 40 }
        var planSize: CGSize { self == .calm ? CGSize(width: 560, height: 288) : CGSize(width: 460, height: 236) }
        var chartHeight: CGFloat { self == .calm ? 200 : 180 }
        /// Minimum height of the Overview first screen (keeps the fold where the board measured it).
        var firstScreenMinHeight: CGFloat { self == .calm ? 588 : 0 }
    }

    // MARK: Radii (concentric: outer = inner + padding)
    enum Radius {
        static let budgetOverrun: CGFloat = 1
        static let budgetFill: CGFloat = 2
        static let tile: CGFloat = RoomDS.Radius.tile
        static let field: CGFloat = RoomDS.Radius.field
        static let row: CGFloat = RoomDS.Radius.row
        static let card: CGFloat = RoomDS.Radius.card
        static let group: CGFloat = RoomDS.Radius.group
        static let popover: CGFloat = RoomDS.Radius.popover
        static let sheet: CGFloat = RoomDS.Radius.sheet
        static let planRoom: CGFloat = RoomDS.Radius.planRoom
        static let plan: CGFloat = 11
    }

    /// The first-run welcome: three wordless scenes (title, one line, a graphic). Stage sizes live in `RoomOnboardingStage`.
    enum Onboarding {
        static let width: CGFloat = RoomDS.Layout.onboardingSheet.width
        static let height: CGFloat = RoomDS.Layout.onboardingSheet.height
        static let maxHeight: CGFloat = 600
        static let top: CGFloat = 40
        static let side: CGFloat = 40
        static let bottom: CGFloat = 24
        static let pipsHeight: CGFloat = 12
        static let titleToLine: CGFloat = 6
        static let headerHeight: CGFloat = 92
        static let headerToStage: CGFloat = 24
        static let footerHeight: CGFloat = 34
        static let linkGap: CGFloat = 20
        /// Progress pips: the current one stretches into a capsule.
        static let pip: CGFloat = 6
        static let pipCurrent: CGFloat = 22
        static let pipGap: CGFloat = 6
        /// Display face (Fraunces) for the title and the one big number; SF for everything else.
        static let title = RoomDS.TypeRole.displayXl.font
        static let titleTracking: CGFloat = RoomDS.TypeRole.displayXl.spec.tracking
        static let line = RoomDS.TypeRole.lead.font
        static let bigNumber = Font.custom(RoomDS.displayFamilyName, fixedSize: 76).weight(.semibold)
        static let bigNumberTracking: CGFloat = -1.6
        static let bigUnit = Font.system(size: 15, weight: .medium)
        static let numberPopFrom: CGFloat = 0.82
        static let numberDelay: TimeInterval = 0.18
        /// Rings: centres from the shared RoomDotPlan, drawn larger than Overview's so the scene reads at a glance.
        static let ringRadiusFactor: CGFloat = 0.34
        static let ringRadiusMax: CGFloat = 10
        static let ringStroke: CGFloat = 1.5
        static let ringPopFrom: CGFloat = 0.2
        /// Pointer swell: rings within `swellReach` grow by up to `swellGain`, then relax. No motion at rest.
        static let swellReach: CGFloat = 76
        static let swellGain: CGFloat = 0.7
        static let wallStroke: CGFloat = 1
        /// Used space Room has not looked inside: quiet points on the ring lattice, never a guess.
        static let usedPoint: CGFloat = 1.4
        static let usedPointOpacity: Double = 0.4
        /// The step 2 example: three rooms of filled dots, a Trash, a Put back link.
        static let exampleDot: CGFloat = 3.4
        static let examplePitch: CGFloat = 14
        static let trashSize: CGFloat = 104
        static let trashGlyph = Font.system(size: 34, weight: .regular)
        static let trashLanded: CGFloat = 0.16
        static let roomLift: CGFloat = 1.04
        static let nudge: CGFloat = 8
        static let nudgeDelay: Duration = .milliseconds(1100)
        static let chipGlyph = Font.system(size: 10, weight: .semibold)
        /// Step 3 tiles: one filled (Map my home folder), two quiet.
        static let tileHeight: CGFloat = 140
        static let tileGap: CGFloat = 16
        static let tileGlyph = Font.system(size: 30, weight: .regular)
        static let tileHover: CGFloat = 1.035
        static let tilePress: CGFloat = 0.95
        static let stageToTiles: CGFloat = 20
        /// The finishing mark: pops, then the sheet closes.
        static let markSize: CGFloat = 72
        static let markHold: Duration = .milliseconds(420)
        static let markOpacity: Double = 0.55
        static let notMappedOpacity: Double = 0.6
        static let disabledOpacity: Double = 0.55
    }

    enum Sidebar {
        static let iconWidth: CGFloat = 16
        static let innerPadding: CGFloat = 8
        static let pitchGap: CGFloat = 2
        static let barHeight: CGFloat = 4
        static let minimumTarget: CGFloat = 24
    }

    // MARK: Identity
    enum Settings {
        static let width: CGFloat = 620
        static let appIconSize: CGFloat = 104
        static let folderRowHeight: CGFloat = 52
        static let folderListMaximumHeight: CGFloat = 260
    }

    enum Ink {
        static let graphite = Color.room(RoomDS.Product.ink, name: "room.ink")
        static let secondary = Color.room(RoomDS.Product.ink2, name: "room.ink2")
        static let iconGraphite = Color(nsColor: NSColor(roomHex: RoomDS.Product.iconTile.light.hex))  // icon tile, both modes
    }

    enum Surface {
        static let canvas = Color.room(RoomDS.Product.canvas, name: "room.canvas")
        static let group = Color.room(RoomDS.Product.group, name: "room.group")
        static let track = Color.room(RoomDS.Product.track, name: "room.track")
        static let used = Color.room(RoomDS.Product.used, name: "room.used")
        static let hover = Color.room(RoomDS.Product.hover, name: "room.hover")
        static let press = Color.room(RoomDS.Product.press, name: "room.press")
        static let line = Color.room(RoomDS.Product.line, name: "room.line")
        static let line2 = Color.room(RoomDS.Product.line2, name: "room.line2")
        static let hatch = Color.room(RoomDS.Product.hatch, name: "room.hatch")
    }

    // MARK: Accent (Customise: four options). fill = filled button and data; text = links and selected text.
    enum Accent: String, CaseIterable, Codable, Sendable {
        case teal, graphite, harbour, berry
        var title: String { rawValue.capitalized }
        var fill: Color {
            switch self {
            case .teal: .room(RoomDS.Accent.fill, name: "room.accent.teal.fill")
            case .graphite: .room(light: 0x3A4146, dark: 0x596167, name: "room.accent.graphite.fill")
            case .harbour: .room(light: 0x3A6491, dark: 0x3A6289, name: "room.accent.harbour.fill")
            case .berry: .room(light: 0x8A4766, dark: 0x84476A, name: "room.accent.berry.fill")
            }
        }
        var text: Color {
            switch self {
            case .teal: .room(RoomDS.Accent.text, name: "room.accent.teal.text")
            case .graphite: .room(light: 0x3A4146, dark: 0xD2D8DB, name: "room.accent.graphite.text")
            case .harbour: .room(light: 0x3A6491, dark: 0x8DB4DD, name: "room.accent.harbour.text")
            case .berry: .room(light: 0x8A4766, dark: 0xDDA6C0, name: "room.accent.berry.text")
            }
        }
        /// 10 % (light) / 14 % (dark) wash of the text step: selection, lamp, hover on accent rows.
        var wash: Color {
            switch self {
            case .teal: .room(RoomDS.Accent.wash, name: "room.accent.teal.wash")
            case .graphite: .room(light: 0x3A4146, dark: 0xD2D8DB, alphaLight: 0.10, alphaDark: 0.14, name: "room.accent.graphite.wash")
            case .harbour: .room(light: 0x3A6491, dark: 0x8DB4DD, alphaLight: 0.10, alphaDark: 0.14, name: "room.accent.harbour.wash")
            case .berry: .room(light: 0x8A4766, dark: 0xDDA6C0, alphaLight: 0.10, alphaDark: 0.14, name: "room.accent.berry.wash")
            }
        }
    }

    // MARK: Status: memory pressure and the free-space goal only. Never used for data series.
    enum Status {
        static let pressureLaneOpacity = 0.08
        static let normal = Color.room(RoomDS.Status.normal, name: "room.status.normal")
        static let elevated = Color.room(RoomDS.Status.elevated, name: "room.status.elevated")
        static let critical = Color.room(RoomDS.Status.critical, name: "room.status.critical")
        static let elevatedWash = Color.room(RoomDS.Status.elevatedWash, name: "room.status.elevated.wash")
    }

    // MARK: Data: the seven kinds. fill = tiles and plan rooms (labels sit on them); mark = dots, thin bars, sparklines.
    enum Kind: String, CaseIterable, Codable, Sendable {
        case developer, media, documents, apps, archives, system, hidden
        var fill: Color {
            switch self {
            case .developer: .room(RoomDS.Kind.developer.fill, name: "room.kind.dev.fill")
            case .media: .room(RoomDS.Kind.media.fill, name: "room.kind.media.fill")
            case .documents: .room(RoomDS.Kind.documents.fill, name: "room.kind.docs.fill")
            case .apps: .room(RoomDS.Kind.apps.fill, name: "room.kind.apps.fill")
            case .archives: .room(RoomDS.Kind.archives.fill, name: "room.kind.arch.fill")
            case .system: .room(RoomDS.Kind.system.fill, name: "room.kind.sys.fill")
            case .hidden: .room(RoomDS.Kind.hidden.fill, name: "room.kind.hid.fill")
            }
        }
        /// Retuned marks (DS-8): 3:1 on canvas and group, separated for colour-vision deficiency, with Increase Contrast steps.
        var mark: Color {
            switch self {
            case .developer: .room(RoomDS.Kind.developer.mark, name: "room.kind.dev.mark")
            case .media: .room(RoomDS.Kind.media.mark, name: "room.kind.media.mark")
            case .documents: .room(RoomDS.Kind.documents.mark, name: "room.kind.docs.mark")
            case .apps: .room(RoomDS.Kind.apps.mark, name: "room.kind.apps.mark")
            case .archives: .room(RoomDS.Kind.archives.mark, name: "room.kind.arch.mark")
            case .system: .room(RoomDS.Kind.system.mark, name: "room.kind.sys.mark")
            case .hidden: .room(RoomDS.Kind.hidden.mark, name: "room.kind.hid.mark")
            }
        }
        static let tileInk = Color.room(RoomDS.Product.tileInk, name: "room.tile.ink")
        static let tileInk2 = Color.room(RoomDS.Product.tileInk2, name: "room.tile.ink2")
    }

    /// The scan buttons and the scan animation.
    enum Scan {
        static let buttonHeight: CGFloat = 44
        static let buttonMinWidth: CGFloat = 150
        static let heroHeight: CGFloat = 60
        static let heroMinWidth: CGFloat = 240
        static let heroFont = Font.system(size: 17, weight: .semibold)
        static let boardMinHeight: CGFloat = 300
        static let stripHeight: CGFloat = 58
        static let segmentHeight: CGFloat = 10
        static let maxSegments = 24
        /// A finished room's dots step back so the figure leads.
        static let restingDots = 0.45
        /// How long finished rooms stay before the page shows the result. A dwell time, not motion.
        static let settle: TimeInterval = 1.6
    }

    enum Developer {
        static let rowMinHeight: CGFloat = 44
        static let breakdownHeight: CGFloat = 8
        static let breakdownGap: CGFloat = 2
        static let breakdownSteps: [Double] = [1, 0.72, 0.5, 0.34, 0.22]
        static let actionSize: CGFloat = 28
    }

    enum Map {
        static let inspectorWidth: CGFloat = 260
        static let inspectorBreakpoint: CGFloat = 688
        static let minimumHeight: CGFloat = 360
        static let controlsHeight: CGFloat = 36
        static let readoutHeight: CGFloat = 28
        static let largestRowHeight: CGFloat = 23
        static let kindBarHeight: CGFloat = 12
        static let kindHoverOpacity = 0.18
        static let focusStroke: CGFloat = 2
        /// Hover ring inside a tile (the stroke is doubled and clipped, so 1 pt shows inside).
        static let hoverRing: CGFloat = 1
        static let labelPaddingX: CGFloat = 7
        static let labelPaddingY: CGFloat = 3
        static let hatchStroke: CGFloat = 1.5
        static let hatchPitch: CGFloat = 6.5
        static let pendingTileOpacity = 0.34
        static let pendingGroupOpacity = 0.4
        static let blueprintGridPitch: CGFloat = 12
        static let blueprintGridDot: CGFloat = 1
        static let blueprintWallStroke: CGFloat = 1
    }

    // MARK: Motion values (the environment value in RoomMotion folds in Gentle motion + Reduce Motion)
    /// Motion (DS-9): four durations from RoomDS (quick 120, standard 200, page 320, slow 600 ms), the ease-out curve,
    /// the page spring and one overshoot. Everything below is either one of those or a named choreography parameter
    /// (v4 board) that is not a duration. No other timing literals in the app.
    enum Motion {
        static let quick = RoomDS.Motion.timed(.quick)
        static let standard = RoomDS.Motion.timed(.standard)
        static let pageResponse = RoomDS.Motion.Spring.page.spec.response
        static let page = RoomDS.Motion.Spring.page.spec.animation
        static let success = RoomDS.Motion.Spring.success.spec.animation  // the only overshoot
        /// The welcome's play (owner brief 2026-11-24: "be playful"): light springs that settle in one bounce.
        /// Onboarding only; the product keeps `success` as its one overshoot.
        static let pop = Animation.spring(response: 0.42, dampingFraction: 0.62)
        static let hop = Animation.spring(response: 0.46, dampingFraction: 0.78)
        static let swell = Animation.spring(response: 0.3, dampingFraction: 0.55)
        static let bounce = Animation.spring(response: 0.26, dampingFraction: 0.5)
        nonisolated static let popSpread: TimeInterval = 0.55
        /// Reduce Motion fallback and the Hide dissolve: 150 ms (REVIEW §4.7 keeps Hide at 150 ms).
        nonisolated static let fadeDuration: TimeInterval = 0.15
        nonisolated static let fadeCurve = UnitCurve.easeOut
        static let fade = Animation.timingCurve(fadeCurve, duration: fadeDuration)
        static let count: TimeInterval = RoomDS.Motion.Duration.page.seconds
        static let countAnimation = Animation.easeOut(duration: count)
        nonisolated static let stagger: TimeInterval = RoomDS.Motion.staggerItem
        static let groupStagger: TimeInterval = RoomDS.Motion.staggerGroup
        static let maxStaggered = RoomDS.Motion.staggerCap
        static let tooltipDelay: TimeInterval = RoomDS.Motion.tooltipDelay
        static let pressScale: CGFloat = RoomDS.Motion.pressScale

        // Board v4 choreography parameters (room-design-v4/src/10-body.html:243-248), not durations.
        /// Odometer: 260 ms per column.
        static let odometerColumn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.26)
        /// Motion.trace: the pill's dash, one lap per 1.4 s, linear, 22 % of the outline. Only while a scan runs.
        static let traceLap: TimeInterval = 1.4
        static let traceDashFraction: CGFloat = 0.22
        /// Motion.coast: spring without overshoot whose response grows with distance, 0.26 … 0.62 s.
        static func coast(distanceGB: Double) -> Animation {
            .spring(response: min(0.62, 0.26 + abs(distanceGB) * 0.003), dampingFraction: 1)
        }
        /// Motion.morph: Your week range / mode morph, page duration, ease-in-out cubic.
        nonisolated static let morphDuration: TimeInterval = RoomDS.Motion.Duration.page.seconds
        nonisolated static let morphCurve = UnitCurve.bezier(startControlPoint: .init(x: 0.65, y: 0),
                                               endControlPoint: .init(x: 0.35, y: 1))
        nonisolated static let historyDotDuration: TimeInterval = 0.22
        nonisolated static let historyDotRise: CGFloat = 6
        /// Small controls (B4 d41, d42): inline confirm armed 4 s, Undo 8 s. Dwell times, not motion.
        static let confirmArmed: TimeInterval = 4
        static let undoWindow: TimeInterval = 8
    }

    /// Dot plan drawing (board v4 `planDotsSVG`): radius from pitch, free rings, dimming.
    enum Dots {
        static let radiusFactor: CGFloat = 0.15, minRadius: CGFloat = 2.4, maxRadius: CGFloat = 3.6
        static let freeRingStroke: CGFloat = 1.2
        static let freeRingOpacity: Double = 0.8           // Ink.secondary at 80 %: 3.7:1 light, 5.2:1 dark
        static let dimmedOpacity: Double = 0.18            // other kinds while one is lit
        static let quietLabels = 3                         // the three largest rooms keep a label
        static let quietLabelMinSize = CGSize(width: 64, height: 22)
        static let lampFalloff: CGFloat = 110              // label opacity 1.25 − d / 110
        static let blueprintGridFactor: CGFloat = 0.5      // unmeasured grid at half pitch
        static let blueprintWall: TimeInterval = 0.36, blueprintFill: TimeInterval = 0.30
    }

    // MARK: Performance budgets (18-BUILD-PLAN-AND-TESTS.md gate G7)
    enum Budget {
        static let frameMilliseconds: Double = 8.3        // 120 Hz ProMotion; 16.7 is the hard ceiling
        static let maxDots = 320
        static let maxCanvasTiles = 600
        static let idleCPUPercent: Double = 0.5
        static let residentMegabytes: Double = 150
    }
}

// MARK: - Motion environment

/// Resolved once per window from `@AppStorage("RoomMotionEnabled")` and `accessibilityReduceMotion`.
struct RoomMotionPolicy: Equatable, Sendable {
    var gentleMotion: Bool
    var reduceMotion: Bool
    /// Full motion only when both allow it.
    var isFull: Bool { gentleMotion && !reduceMotion }
    /// Spatial animation, or the 150 ms fade fallback, or nothing (nil = instant).
    func animation(_ full: Animation, fallback: Animation? = RoomTokens.Motion.fade) -> Animation? {
        isFull ? full : fallback
    }
}

private struct RoomMotionKey: EnvironmentKey {
    static let defaultValue = RoomMotionPolicy(gentleMotion: true, reduceMotion: false)
}

extension EnvironmentValues {
    var roomMotion: RoomMotionPolicy {
        get { self[RoomMotionKey.self] }
        set { self[RoomMotionKey.self] = newValue }
    }
}

/// Applied once at each scene root (main window, Settings, popover hosting view).
struct RoomMotionRoot: ViewModifier {
    @AppStorage("RoomMotionEnabled") private var gentle = true
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content.environment(\.roomMotion, RoomMotionPolicy(gentleMotion: gentle, reduceMotion: reduce))
    }
}

// MARK: - Button styles (no inline tints anywhere else)

struct RoomPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(RoomPressFeedback(pressed: configuration.isPressed))
    }
}

private struct RoomPressFeedback: ViewModifier {
    let pressed: Bool
    @Environment(\.roomMotion) private var motion
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && motion.isFull ? RoomTokens.Motion.pressScale : 1)
            .opacity(pressed && !motion.isFull ? 0.7 : 1)
            .animation(motion.isFull ? RoomTokens.Motion.press : nil, value: pressed)
    }
}

private struct RoomScreenPrimaryStyle: ButtonStyle {
    let accent: RoomTokens.Accent
    var hero = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(hero ? RoomTokens.Scan.heroFont : RoomTokens.Typography.bodyStrong)
            .padding(.horizontal, hero ? RoomTokens.Space.breath1 : RoomTokens.Space.group + 2)
            .frame(minWidth: hero ? RoomTokens.Scan.heroMinWidth : RoomTokens.Scan.buttonMinWidth,
                   minHeight: hero ? RoomTokens.Scan.heroHeight : RoomTokens.Scan.buttonHeight)
            .foregroundStyle(enabled ? Color.white : RoomTokens.Ink.secondary)
            .background(enabled ? accent.fill : RoomTokens.Surface.track, in: Capsule())
            .brightness(hovering && enabled ? 0.05 : 0)
            .contentShape(Capsule())
            .onHover { inside in withAnimation(RoomTokens.Motion.hover) { hovering = inside } }
            .modifier(RoomPressFeedback(pressed: configuration.isPressed))
    }
}

private struct RoomQuietStyle: ButtonStyle {
    var hero = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RoomTokens.Typography.bodyStrong)
            .padding(.horizontal, RoomTokens.Space.group)
            .frame(minWidth: hero ? RoomTokens.Scan.buttonMinWidth : nil,
                   minHeight: hero ? RoomTokens.Scan.buttonHeight : RoomTokens.Overview.actionHeight)
            .foregroundStyle(enabled ? RoomTokens.Ink.graphite : RoomTokens.Ink.tertiary)
            .background(RoomTokens.Surface.tile, in: Capsule())
            .contentShape(Capsule())
            .modifier(RoomPressFeedback(pressed: configuration.isPressed))
    }
}

extension View {
    /// The one filled button per context: native prominent glass in the accent fill.
    func roomPrimary(_ accent: RoomTokens.Accent) -> some View {
        buttonStyle(.glassProminent).tint(accent.fill).controlSize(.large)
    }
    /// `hero`: the large centre-stage form a scan button takes before a screen has anything to show.
    func roomScreenPrimary(_ accent: RoomTokens.Accent, hero: Bool = false) -> some View {
        buttonStyle(RoomScreenPrimaryStyle(accent: accent, hero: hero))
    }
    /// The quiet pill beside a filled button (mockup `.quiet`: Cancel in a review).
    func roomQuiet(large: Bool = false) -> some View { buttonStyle(RoomQuietStyle(hero: large)) }
    /// Secondary actions: ordinary, untinted glass. The scene root tints everything with the accent, and tinted glass
    /// reads as a second filled button, so secondary buttons drop the tint (one filled button per screen).
    func roomSecondary(_ size: ControlSize = .large) -> some View { buttonStyle(.glass).tint(nil).controlSize(size) }
    /// Quiet links ("See what is using space", "Your week ›"): plain, accent text step, 24 pt hit target.
    func roomLink(_ accent: RoomTokens.Accent) -> some View {
        buttonStyle(RoomPressStyle()).foregroundStyle(accent.text).frame(minHeight: 24).contentShape(Rectangle())
    }
}

// MARK: - Accent environment (set once per scene root from @AppStorage("RoomAccent"))

private struct RoomAccentKey: EnvironmentKey {
    static let defaultValue = RoomTokens.Accent.teal
}

extension EnvironmentValues {
    var roomAccent: RoomTokens.Accent {
        get { self[RoomAccentKey.self] }
        set { self[RoomAccentKey.self] = newValue }
    }
}

struct RoomAccentRoot: ViewModifier {
    @AppStorage("RoomAccent") private var accent = RoomTokens.Accent.teal
    func body(content: Content) -> some View {
        content.environment(\.roomAccent, accent).tint(accent.fill)
    }
}
