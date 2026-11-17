// Room menu bar: the pure presentation (MBF-2). Foundation only, no AppKit, no SwiftUI.
// Copy to Sources/RoomApp/RoomMenuBarPresentation.swift. It replaces the status-item half of RoomMonitorPresentation.
// Spec: MENU-BAR-SPEC.md §3 (the eight states), §3.3 (announcements), §3.5 (motion).
// Every type is `nonisolated` so the RoomApp target's default MainActor isolation does not apply to it.
import Foundation

nonisolated enum RoomMenuBarValueMode: String, CaseIterable, Sendable { case memory, disk, both, none }
nonisolated enum RoomMenuBarLayoutMode: String, CaseIterable, Sendable { case inline, stacked }
nonisolated enum RoomMenuBarIconMode: String, CaseIterable, Sendable { case mark, symbol, none }
nonisolated enum RoomMenuBarPressure: Sendable { case unknown, normal, elevated, critical }

/// Severity of what the item shows. Raw values rank it, so the "worse of" rule (MB-4) is `max`.
nonisolated enum RoomMenuBarLevel: Int, Comparable, Sendable {
    case normal = 0, elevated = 1, critical = 2
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Which Status colour tints the icon. `.none` means "no tint, the template follows the menu bar".
nonisolated enum RoomMenuBarTint: Equatable, Sendable { case none, normal, elevated, critical }

nonisolated struct RoomMenuBarInput: Equatable, Sendable {
    var value: RoomMenuBarValueMode = .memory
    var layout: RoomMenuBarLayoutMode = .inline
    var icon: RoomMenuBarIconMode = .mark
    var tintOnlyWhenNeeded = true          // "Colour only when it matters" (MB-3)
    var memoryUsedBytes: Int64?            // nil: unavailable
    var memoryTotalBytes: Int64?
    var pressure: RoomMenuBarPressure = .unknown
    var diskFreeBytes: Int64?              // nil: unavailable
    var goalBytes: Int64 = 0               // 0: no goal (the app never stores 0; this is defensive)
}

nonisolated struct RoomMenuBarStackedLine: Equatable, Sendable {
    var symbolName: String
    var text: String
}

nonisolated struct RoomMenuBarOutput: Equatable, Sendable {
    var title: String                      // "" when Value is None
    var icon: RoomMenuBarIconMode          // effective icon (MB-5 can force `.mark`)
    var symbolName: String                 // used when icon == .symbol
    var pocketFill: Double                 // 0, 0.5 or 1 (only for icon == .mark)
    var tint: RoomMenuBarTint
    var accessibilityValue: String
    var toolTip: String                    // "Room · " + accessibilityValue (MB-8)
    var announcementKey: String            // changes only when the tone changes (MB-7)
    var stackedLines: [RoomMenuBarStackedLine]? = nil
}

/// The app passes RoomFormat; the checks pass `fixtureGigabytes`.
nonisolated struct RoomMenuBarFormat: Sendable {
    var memory: @Sendable (Int64) -> String
    var disk: @Sendable (Int64) -> String

    /// Decimal gigabytes: memory with one decimal and no trailing ".0" ("16.2 GB", "32 GB"), disk with none ("312 GB").
    static let fixtureGigabytes = RoomMenuBarFormat(
        memory: { bytes in gigabytes(bytes, decimals: 1) },
        disk: { bytes in gigabytes(bytes, decimals: 0) })

    private static func gigabytes(_ bytes: Int64, decimals: Int) -> String {
        var s = String(format: "%.\(decimals)f", Double(bytes) / 1e9)
        if decimals > 0, s.hasSuffix(".0") { s.removeLast(2) }
        return s + " GB"
    }
}

extension RoomMenuBarFormat {
    /// What the status item and the popover show. Memory in binary gigabytes like Activity Monitor with one decimal
    /// ("38.5 GB", "48 GB"; the system formatter gave "38.53 GB"). Free disk in decimal gigabytes like Finder: whole from
    /// 10 GB up ("312 GB"), one decimal below ("4.2 GB"), terabytes with one decimal ("1.2 TB").
    static let live = RoomMenuBarFormat(
        memory: { liveMemory($0) },
        disk: { liveDisk($0) })

    nonisolated static func liveMemory(_ bytes: Int64, locale: Locale = .current) -> String {
        if bytes <= 0 { return "0 KB" }
        let mib = (Double(bytes) / 1_048_576).rounded()
        // Pick the unit after rounding: 1,023.6 MiB is "1 GB", not "1,024 MB".
        if mib < 1_024 { return whole(max(mib, 1), locale: locale) + " MB" }
        return trimmed(Double(bytes) / 1_073_741_824, decimals: 1, locale: locale) + " GB"
    }

    nonisolated static func liveDisk(_ bytes: Int64, locale: Locale = .current) -> String {
        if bytes <= 0 { return "0 KB" }
        let value = Double(bytes)
        if value >= 1e12 || (value / 1e9).rounded() >= 1_000 { return trimmed(value / 1e12, decimals: 1, locale: locale) + " TB" }
        if value >= 1e10 { return whole((value / 1e9).rounded(), locale: locale) + " GB" }
        if value >= 1e9 {
            let tenths = (value / 1e8).rounded() / 10
            // 9.96 GB rounds to 10.0: show it as a whole figure, like the 10 GB and up rule.
            return tenths >= 10 ? whole(tenths, locale: locale) + " GB" : trimmed(tenths, decimals: 1, locale: locale) + " GB"
        }
        let mb = (value / 1e6).rounded()
        return mb >= 1_000 ? "1 GB" : whole(max(mb, 1), locale: locale) + " MB"
    }

    /// A whole number without grouping separators, in the locale's own digits.
    private nonisolated static func whole(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    private nonisolated static func trimmed(_ value: Double, decimals: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = decimals
        formatter.roundingMode = .halfEven
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
    }
}

nonisolated enum RoomMenuBarPresentation {
    static func make(_ i: RoomMenuBarInput, format f: RoomMenuBarFormat) -> RoomMenuBarOutput {
        // D-MB-14: RAM and storage get their own symbols (memorychip, internaldrive); two metrics or none have no single
        // symbol, so the Room mark stands in. MB-5: no icon and no value would leave an invisible item, so the mark stays.
        var icon: RoomMenuBarIconMode = i.icon
        if icon == .symbol, i.value == .both || i.value == .none { icon = .mark }
        if i.value == .none, icon == .none { icon = .mark }

        let usesMemory = i.value != .disk       // memory, both and none (icon only) read memory
        let usesDisk = i.value != .memory       // disk, both and none read the disk

        let memoryKnown = (i.memoryTotalBytes ?? 0) > 0 && i.memoryUsedBytes != nil
        let diskKnown = i.diskFreeBytes != nil
        let free = i.diskFreeBytes ?? 0
        let hasGoal = i.goalBytes > 0
        let belowGoal = diskKnown && hasGoal && free < i.goalBytes

        let memoryLevel: RoomMenuBarLevel = switch i.pressure {
        case .elevated: .elevated
        case .critical: .critical
        case .normal, .unknown: .normal
        }
        let diskLevel: RoomMenuBarLevel = belowGoal ? .elevated : .normal      // free space is never "critical" (MB-4)
        // MB-4, and the Value-None row: the icon is the only signal, so it carries the worse of the two.
        let level = max(usesMemory ? memoryLevel : .normal, usesDisk ? diskLevel : .normal)

        let fill: Double = switch level { case .normal: 0; case .elevated: 0.5; case .critical: 1 }

        let tint: RoomMenuBarTint
        switch level {
        case .critical: tint = .critical
        case .elevated: tint = .elevated
        case .normal:
            let measuredNormal = (usesMemory && memoryKnown && i.pressure != .unknown) || (usesDisk && diskKnown)
            tint = (!i.tintOnlyWhenNeeded && measuredNormal) ? .normal : .none   // MB-3
        }

        let memoryTitle = memoryKnown ? f.memory(i.memoryUsedBytes ?? 0) : "—"
        let diskNumber = diskKnown ? f.disk(free) : "—"
        let title: String
        switch i.value {
        case .memory: title = memoryTitle
        case .disk: title = diskNumber                     // the number alone: the storage symbol says what it is
        case .both: title = "\(memoryTitle) · \(diskNumber)"
        case .none: title = ""
        }

        let pressureWords: String = switch i.pressure {
        case .normal: "Normal pressure"
        case .elevated: "Elevated pressure"
        case .critical: "Critical pressure"
        case .unknown: "Pressure unavailable"
        }
        let memorySpoken = memoryKnown
            ? "\(f.memory(i.memoryUsedBytes ?? 0)) memory used of \(f.memory(i.memoryTotalBytes ?? 0)), \(pressureWords)"
            : "Memory measurement unavailable"
        let diskSpoken: String
        if !diskKnown { diskSpoken = "Free space unavailable" }
        else if !hasGoal { diskSpoken = "\(f.disk(free)) free" }
        else if belowGoal { diskSpoken = "\(f.disk(free)) free, \(f.disk(i.goalBytes - free)) under your \(f.disk(i.goalBytes)) goal" }
        else { diskSpoken = "\(f.disk(free)) free, at or above your \(f.disk(i.goalBytes)) goal" }
        let spoken: String
        switch i.value {
        case .memory: spoken = memorySpoken
        case .disk: spoken = diskSpoken
        case .both, .none: spoken = "\(memorySpoken). \(diskSpoken)"
        }

        // The key names the tone of each metric in use, so crossing the goal or a pressure step changes it
        // and a change of the number alone does not.
        let key = "m\(usesMemory ? String(memoryLevel.rawValue) : "-")d\(usesDisk ? (belowGoal ? "1" : "0") : "-")"

        return RoomMenuBarOutput(
            title: title, icon: icon,
            symbolName: i.value == .disk ? "internaldrive" : "memorychip",
            pocketFill: fill, tint: tint,
            accessibilityValue: spoken, toolTip: "Room · \(spoken)", announcementKey: key,
            stackedLines: i.layout == .stacked && i.value == .both ? [
                RoomMenuBarStackedLine(symbolName: "memorychip", text: memoryTitle),
                RoomMenuBarStackedLine(symbolName: "internaldrive", text: diskNumber)
            ] : nil)
    }
}

/// MB-7: post `.valueChanged` only when the key changes. The first value after launch is not an event.
nonisolated struct RoomMenuBarAnnouncer: Sendable {
    private(set) var lastKey: String?
    mutating func shouldAnnounce(_ key: String) -> Bool {
        defer { lastKey = key }
        guard let lastKey else { return false }
        return lastKey != key
    }
}

/// The two motions that need numbers (MENU-BAR-SPEC §3.5). Both are pure so they can be unit tested.
nonisolated enum RoomMenuBarMotion {
    /// Cached pocket images: the three keyframes plus six intermediates, all multiples of 1/8.
    static let cachedFills: [Double] = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1]
    static let fillDuration: TimeInterval = 0.2
    static let fillFrameCount = 6

    private static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    /// Six frames between two fills, ease-out, each snapped to a cached image. Ease-out lands on the target early,
    /// so frames repeat (0 → 1 gives 0.375, 0.625, 0.875, 0.875, 1, 1): the renderer skips a frame equal to the one before.
    static func fillFrames(from: Double, to: Double) -> [Double] {
        (1...fillFrameCount).map { k in
            let v = from + (to - from) * easeOut(Double(k) / Double(fillFrameCount + 1))
            return cachedFills.min(by: { abs($0 - v) < abs($1 - v) }) ?? to
        }
    }

    static let tickDuration: TimeInterval = 0.32
    static let tickSteps = 8                    // one title update every 40 ms
    static let tickThreshold = 0.1              // only a change of at least 0.1 counts up

    /// The number shown on each of 8 title updates; the last is exactly `to`. Empty when the change is under 0.1.
    static func tickValues(from: Double, to: Double) -> [Double] {
        guard abs(to - from) >= tickThreshold else { return [] }
        return (1...tickSteps).map { k in
            k == tickSteps ? to : from + (to - from) * easeOut(Double(k) / Double(tickSteps))
        }
    }
}

#if DEBUG
/// Debug-only: forces the menu bar into each state of the spec so the owner can see all of them in a minute.
/// Wired to a "Debug › Menu bar state" menu in MBF-6. Never ships: the file is excluded from release builds by this guard (gate G10).
nonisolated enum RoomDebugMenuBarScenario: String, CaseIterable, Sendable {
    case live, normal, elevated, critical, diskBelowGoal, bothElevatedBelowGoal, bothStacked, iconOnlyElevated

    func apply(to live: RoomMenuBarInput) -> RoomMenuBarInput {
        var i = live
        let gb: Int64 = 1_000_000_000
        func memory(_ used: Double, _ pressure: RoomMenuBarPressure) {
            i.memoryUsedBytes = Int64(used * 1e9); i.memoryTotalBytes = 32 * gb; i.pressure = pressure
        }
        switch self {
        case .live: break
        case .normal: i.value = .memory; memory(16.2, .normal)
        case .elevated: i.value = .memory; memory(24.8, .elevated)
        case .critical: i.value = .memory; memory(30.1, .critical)
        case .diskBelowGoal: i.value = .disk; i.diskFreeBytes = 41 * gb; i.goalBytes = 50 * gb
        case .bothElevatedBelowGoal, .bothStacked:
            i.value = .both
            i.layout = self == .bothStacked ? .stacked : .inline
            memory(24.8, .elevated)
            i.diskFreeBytes = 41 * gb
            i.goalBytes = 50 * gb
        case .iconOnlyElevated: i.value = .none; memory(24.8, .elevated)
        }
        return i
    }
}
#endif
