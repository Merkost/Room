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
    /// The same light and dark pair as a `RoomDS` swatch. Increase Contrast keeps using the light and dark values (DS-5 adopts the HC ones).
    static func room(_ swatch: RoomDS.Swatch, name: String) -> Color {
        room(light: swatch.light.hex, dark: swatch.dark.hex, alphaLight: swatch.light.alpha, alphaDark: swatch.dark.alpha, name: name)
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

    enum Onboarding {
        static let width: CGFloat = 620
        static let height: CGFloat = 540
        static let planWidth: CGFloat = 300
        static let planHeight: CGFloat = 262
        static let supportingWidth: CGFloat = 210
        static let choicePadding: CGFloat = 14
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
        var mark: Color {
            switch self {
            case .developer: .room(light: 0x2E8AA0, dark: 0x4FA9BF, name: "room.kind.dev.mark")
            case .media: .room(light: 0x5F9150, dark: 0x7DB06C, name: "room.kind.media.mark")
            case .documents: .room(light: 0x5F7DBB, dark: 0x7E9BD8, name: "room.kind.docs.mark")
            case .apps: .room(light: 0x9A8A14, dark: 0xBFAE3A, name: "room.kind.apps.mark")
            case .archives: .room(light: 0xCE5660, dark: 0xE87C86, name: "room.kind.arch.mark")
            case .system: .room(light: 0x7F8990, dark: 0x98A2A8, name: "room.kind.sys.mark")
            case .hidden: .room(light: 0x9670AE, dark: 0xB28DCB, name: "room.kind.hid.mark")
            }
        }
        static let tileInk = Color.room(RoomDS.Product.tileInk, name: "room.tile.ink")
        static let tileInk2 = Color.room(RoomDS.Product.tileInk2, name: "room.tile.ink2")
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
    enum Motion {
        static let quick = RoomDS.Motion.timed(.quick)
        static let standard = RoomDS.Motion.timed(.standard)
        static let exit = RoomDS.Motion.timed(.quick)
        static let pageResponse = RoomDS.Motion.Spring.page.spec.response
        static let page = RoomDS.Motion.Spring.page.spec.animation
        static let compareGlide = Animation.spring(response: 0.36, dampingFraction: 1)
        static let receiptLead = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
        static let onboardingText = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24).delay(0.07)
        static let settle = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
        static let success = RoomDS.Motion.Spring.success.spec.animation  // the only overshoot
        nonisolated static let fadeDuration: TimeInterval = 0.15                                // Reduce Motion fallback
        nonisolated static let fadeCurve = UnitCurve.easeOut
        static let fade = Animation.timingCurve(fadeCurve, duration: fadeDuration)
        static let count: TimeInterval = RoomDS.Motion.Duration.page.seconds
        static let countAnimation = Animation.easeOut(duration: count)
        nonisolated static let stagger: TimeInterval = RoomDS.Motion.staggerItem
        static let settleStagger: TimeInterval = 0.07
        static let maxStaggered = RoomDS.Motion.staggerCap
        static let tooltipDelay: TimeInterval = RoomDS.Motion.tooltipDelay
        static let pressScale: CGFloat = RoomDS.Motion.pressScale

        // Board v4 tokens (room-design-v4/src/10-body.html:243-248). Values shared with RoomPure.
        /// Motion.roll: label in 180 ms, out 140 ms, ease-out, 100 % travel; odometer 260 ms per column.
        static let rollIn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
        static let rollOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
        static let odometerColumn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.26)
        /// Motion.trace: the pill's dash, one lap per 1.4 s, linear, 22 % of the outline. Only while a scan runs.
        static let traceLap: TimeInterval = 1.4
        static let traceDashFraction: CGFloat = 0.22
        /// Motion.coast: spring without overshoot whose response grows with distance, 0.26 … 0.62 s.
        static func coast(distanceGB: Double) -> Animation {
            .spring(response: min(0.62, 0.26 + abs(distanceGB) * 0.003), dampingFraction: 1)
        }
        /// Motion.morph: Your week range / mode morph, 340 ms ease-in-out cubic.
        nonisolated static let morphDuration: TimeInterval = 0.34
        nonisolated static let morphCurve = UnitCurve.bezier(startControlPoint: .init(x: 0.65, y: 0),
                                               endControlPoint: .init(x: 0.35, y: 1))
        nonisolated static let historyDotDuration: TimeInterval = 0.22
        nonisolated static let historyDotRise: CGFloat = 6
        /// Motion.wake: parameters live in RoomPure (34 pt, τ 150 ms, gain 1.2, ring 0.42 pt/ms); the drawn ring lasts 650 ms.
        static let ringDrawn: TimeInterval = 0.65
        /// Pill width spring and history stack spring (both without overshoot).
        static let pillWidth = Animation.spring(response: 0.26, dampingFraction: 1)
        static let stackApart = Animation.spring(response: 0.32, dampingFraction: 1)
        static func stackDelay(_ index: Int) -> TimeInterval { 0.06 + 0.04 * Double(index) }
        /// Small controls (B4 d41, d42): inline confirm armed 4 s, Undo 8 s; list skeleton hold 560 ms, rows 260 ms, 60 ms apart.
        static let confirmArmed: TimeInterval = 4
        static let undoWindow: TimeInterval = 8
        static let skeletonHold: TimeInterval = 0.56
        static let skeletonRow = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.26)
        static let skeletonStagger: TimeInterval = 0.06
        /// Sidebar collapse: labels 100 ms, then the panel 220 ms starting at 110 ms.
        static let sidebarLabels = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.10)
        static let sidebarWidth = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
        static let sidebarPanel = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22).delay(0.11)
        /// Make room: stage 1 lift 260 ms, 16 ms per dot; stage 2 lights 640 ms per dot, 60 ms apart.
        static let liftDuration: TimeInterval = 0.26, liftPerDot: TimeInterval = 0.016
        static let lightDuration: TimeInterval = 0.64, lightPerDot: TimeInterval = 0.06
        /// Hide: 22 ms per character; hold 280 ms to peek.
        static let hidePerCharacter: TimeInterval = 0.022, peekHold: TimeInterval = 0.28
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
            .animation(motion.isFull ? RoomTokens.Motion.quick : nil, value: pressed)
    }
}

private struct RoomScreenPrimaryStyle: ButtonStyle {
    let accent: RoomTokens.Accent
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RoomTokens.Typography.bodyStrong)
            .padding(.horizontal, RoomTokens.Space.group)
            .frame(minHeight: RoomTokens.Overview.actionHeight)
            .foregroundStyle(enabled ? Color.white : RoomTokens.Ink.secondary)
            .background(enabled ? accent.fill : RoomTokens.Surface.track, in: Capsule())
            .contentShape(Capsule())
            .modifier(RoomPressFeedback(pressed: configuration.isPressed))
    }
}

extension View {
    /// The one filled button per context: native prominent glass in the accent fill.
    func roomPrimary(_ accent: RoomTokens.Accent) -> some View {
        buttonStyle(.glassProminent).tint(accent.fill).controlSize(.large)
    }
    func roomScreenPrimary(_ accent: RoomTokens.Accent) -> some View {
        buttonStyle(RoomScreenPrimaryStyle(accent: accent))
    }
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
