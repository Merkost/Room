import SwiftUI

/// The one number formatter (BRAND-DS §4, DS-7). Every byte figure in the app goes through here.
/// - Whole units everywhere ("64 GB", "480 MB", "1.2 TB" for terabytes).
/// - The single hero figure per screen may show one decimal below 100 GB ("63.7 GB").
/// - Lower bounds read "≥ 120 GB", approximations "≈ 2 GB", a missing value reads "not measured".
/// Disk sizes are decimal (Finder); memory sizes are binary (Activity Monitor), with the same rules.
nonisolated enum RoomFormat {
    /// What a value Room did not measure reads as. Words, never a dash.
    static var notMeasured: String { String(localized: "format.notMeasured", defaultValue: "not measured") }

    /// A disk size for any surface except the hero figure.
    static func gb(_ bytes: Int64) -> String { gb(bytes, hero: false) }

    /// A disk size; `hero` keeps one decimal below 100 GB for the screen's one headline figure.
    static func gb(_ bytes: Int64, hero: Bool, locale: Locale = .current) -> String {
        guard bytes > 0 else { return "0 KB" }
        let value = Double(bytes)
        if value >= 1e12 || (value / 1e9).rounded() >= 1_000 {
            return number(value / 1e12, decimals: 1, keepsZero: false, locale: locale) + " TB"
        }
        if value >= 1e9 || (value / 1e6).rounded() >= 1_000 {
            let gigabytes = value / 1e9
            if hero, (gigabytes * 10).rounded() / 10 < 100 {
                return number(gigabytes, decimals: 1, keepsZero: true, locale: locale) + " GB"
            }
            return number(gigabytes, decimals: 0, keepsZero: false, locale: locale) + " GB"
        }
        if value >= 1e6 || (value / 1e3).rounded() >= 1_000 {
            return number(value / 1e6, decimals: 0, keepsZero: false, locale: locale) + " MB"
        }
        return number(max(1, value / 1e3), decimals: 0, keepsZero: false, locale: locale) + " KB"
    }

    /// A disk size that may be missing: nil reads "not measured".
    static func gb(_ bytes: Int64?, hero: Bool = false, partial: Bool = false, locale: Locale = .current) -> String {
        guard let bytes else { return notMeasured }
        let text = gb(bytes, hero: hero, locale: locale)
        return partial ? lowerBound(text) : text
    }

    /// A memory size (binary units). The Memory hero ("In use") keeps one decimal below 100 GB, like the menu bar.
    static func memory(_ bytes: Int64) -> String { memory(bytes, hero: false) }

    static func memory(_ bytes: Int64, hero: Bool, locale: Locale = .current) -> String {
        guard bytes > 0 else { return "0 KB" }
        let mebibytes = (Double(bytes) / 1_048_576).rounded()
        if mebibytes < 1_024 { return number(max(1, mebibytes), decimals: 0, keepsZero: false, locale: locale) + " MB" }
        let gibibytes = Double(bytes) / 1_073_741_824
        if hero, (gibibytes * 10).rounded() / 10 < 100 {
            return number(gibibytes, decimals: 1, keepsZero: false, locale: locale) + " GB"
        }
        return number(gibibytes, decimals: 0, keepsZero: false, locale: locale) + " GB"
    }

    /// "≥ 120 GB": a total that is at least this much (a partial measurement).
    static func lowerBound(_ text: String) -> String { "≥ \(text)" }
    static func lowerBound(_ bytes: Int64) -> String { lowerBound(gb(bytes)) }
    /// "≈ 2 GB": a rounded stand-in, such as the size of one plan dot.
    static func approx(_ text: String) -> String { "≈ \(text)" }
    static func approx(_ bytes: Int64) -> String { approx(gb(bytes)) }

    /// Splits "63.7 GB" into the figure and its unit so the unit can ride the figure's baseline.
    static func split(_ text: String) -> (value: String, unit: String) {
        guard let separator = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }

    static func splitBytes(_ bytes: Int64, memory: Bool = false, hero: Bool = false) -> (value: String, unit: String) {
        split(memory ? self.memory(bytes, hero: hero) : gb(bytes, hero: hero))
    }

    /// Plain grouping-free digits in the locale's own numerals; `keepsZero` keeps "64.0" so the hero never changes width.
    private static func number(_ value: Double, decimals: Int, keepsZero: Bool, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = keepsZero ? decimals : 0
        formatter.maximumFractionDigits = decimals
        let scale = pow(10, Double(decimals))
        let rounded = (value * scale).rounded() / scale
        return formatter.string(from: NSNumber(value: rounded)) ?? String(format: "%.\(decimals)f", rounded)
    }
}

enum RoomType {
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func figure(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
}

/// Each alternative keeps its unit and baseline together. Narrow windows choose
/// the next complete size rather than clipping a unit or compressing its glyphs.
struct RoomByteMetric: View {
    let bytes: Int64
    var maximumSize: CGFloat = 38
    var memory = false
    /// The screen's one hero figure: one decimal below 100 GB.
    var hero = false
    var animatesChanges = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            metric(size: maximumSize).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.82).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.66).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(size: CGFloat) -> some View {
        let amount = RoomFormat.splitBytes(bytes, memory: memory, hero: hero)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Group {
                if memory { Text(amount.value) } else { RoomMaskable(amount.value) }
            }
                .font(RoomType.figure(size))
                .tracking(size > 30 ? -0.5 : 0)
                .monospacedDigit()
                .roomNumericTransition(amount.value, enabled: animatesChanges)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(amount.unit)
                .font(RoomType.figure(max(14, size * 0.4)))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}
