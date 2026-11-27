// Room menu bar popover: the pure data behind the cards (MBF-4 and MBF-7). Foundation only, no AppKit, no SwiftUI.
// Copy to Sources/RoomApp/RoomPopoverModel.swift. Spec: POPOVER-SPEC.md §4 to §6.
// Every type is `nonisolated` so the RoomApp target's default MainActor isolation does not apply to it.
import Foundation

// MARK: - Memory samples and the sparkline (memory card)

/// The last hour of memory use, one sample per 20 s monitor tick, oldest first. In memory only: it starts empty at launch.
nonisolated struct RoomMemorySampleRing: Equatable, Sendable {
    static let capacity = 180
    struct Sample: Equatable, Sendable {
        let at: Date
        let bytes: Int64
        /// Pressure read with this sample; nil when macOS didn’t report one.
        var level: RoomPressureLevel? = nil
    }

    private(set) var samples: [Sample] = []
    var values: [Int64] { samples.map(\.bytes) }

    mutating func append(_ bytes: Int64, at: Date = Date(), level: RoomPressureLevel? = nil) {
        samples.append(Sample(at: at, bytes: bytes, level: level))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }
}

nonisolated enum RoomSparkline {
    static let minimumSamples = 3
    /// A flat hour must not look like a mountain range: the vertical range is at least 1 GB, centred on the data.
    static let minimumSpanBytes = 1_000_000_000.0
    static let inset = 2.0

    /// Polyline points in a `width` x `height` box, first sample at x = 0 and last at x = width, `inset` above and below.
    /// Empty below three samples: the card keeps its 22 pt of height and draws nothing.
    static func points(_ values: [Int64], width: Double, height: Double) -> [(x: Double, y: Double)] {
        guard values.count >= minimumSamples, width > 0, height > 2 * inset,
              let low = values.min(), let high = values.max() else { return [] }
        var bottom = Double(low)
        var span = Double(high) - Double(low)
        if span < minimumSpanBytes {
            bottom = (Double(low) + Double(high)) / 2 - minimumSpanBytes / 2
            span = minimumSpanBytes
        }
        let last = Double(values.count - 1)
        return values.enumerated().map { index, value in
            (x: Double(index) * width / last,
             y: height - inset - (Double(value) - bottom) / span * (height - 2 * inset))
        }
    }
}

// MARK: - The caches card

/// The figure, date and completeness of the last COMPLETED Caches scan. Stored in three defaults keys by the view model.
nonisolated struct RoomCachesCheck: Equatable, Codable, Sendable {
    var at: Date
    var bytes: Int64
    var partial: Bool

    func title(format: (Int64) -> String) -> String {
        if bytes <= 0 { return "No caches to clear" }
        return "\(partial ? "≥ " : "")\(format(bytes)) of caches can go"
    }

    /// "Checked just now" · "Checked today" · "Checked yesterday" · "Checked 3 days ago" · "Checked on 3 Nov" (from 7 days on).
    func caption(now: Date, calendar: Calendar) -> String {
        if now.timeIntervalSince(at) < 60 { return "Checked just now" }
        if calendar.isDate(at, inSameDayAs: now) { return "Checked today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: at), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "Checked yesterday" }
        if days >= 2, days <= 6 { return "Checked \(days) days ago" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return "Checked on \(formatter.string(from: at))"
    }
}

// MARK: - The Room card: size points and "since Monday"

nonisolated struct RoomSizePoint: Equatable, Codable, Sendable {
    var at: Date
    var bytes: Int64
    var partial: Bool          // a lower bound: some folders could not be read
}

nonisolated enum RoomRoomChange: Equatable, Sendable {
    case tracking                                   // one point, or none from before today: "Tracking from today"
    case partial                                    // a point is a lower bound: no delta is shown
    case since(label: String, deltaBytes: Int64)    // label is "Monday", or the weekday of the first point this week
}

/// One point per local day (the last measurement of the day), 120 days, oldest first.
nonisolated struct RoomSizeLog: Equatable, Codable, Sendable {
    static let retentionDays = 120
    /// Below this a change is "No change": 10 MB.
    static let noChangeBytes: Int64 = 10_000_000
    private(set) var points: [RoomSizePoint] = []

    mutating func record(_ point: RoomSizePoint, calendar: Calendar) {
        if let last = points.last {
            guard point.at >= last.at else { return }                       // a clock that went backwards is ignored
            if calendar.isDate(last.at, inSameDayAs: point.at) { points[points.count - 1] = point }
            else { points.append(point) }
        } else {
            points.append(point)
        }
        if let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: point.at) {
            points.removeAll { $0.at < cutoff }
        }
    }

    var latest: RoomSizePoint? { points.last }

    /// Monday 00:00 local of the week containing `date`, whatever the person's region says the week starts on.
    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        var monday = calendar
        monday.firstWeekday = 2
        monday.minimumDaysInFirstWeek = 4
        return monday.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The baseline is the last point from the week before this Monday (at most 7 days before it); if Room did not see
    /// last week, the first point of this week, named by its weekday. Never a point older than that: "since Monday"
    /// must not quietly mean "since three weeks ago".
    func change(now: Date, calendar: Calendar) -> RoomRoomChange {
        guard let latest, latest.at >= Self.weekStart(containing: now, calendar: calendar) else { return .tracking }
        let weekStart = Self.weekStart(containing: now, calendar: calendar)
        let earlier = points.dropLast()
        let lastWeekFloor = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let baseline: RoomSizePoint
        let label: String
        if let before = earlier.last(where: { $0.at < weekStart && $0.at >= lastWeekFloor }) {
            baseline = before
            label = "Monday"
        } else if let first = earlier.first(where: { $0.at >= weekStart }) {
            baseline = first
            label = Self.weekdayName(first.at, calendar: calendar)
        } else {
            return .tracking
        }
        if baseline.partial || latest.partial { return .partial }
        return .since(label: label, deltaBytes: latest.bytes - baseline.bytes)
    }

    static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    func sizeText(format: (Int64) -> String) -> String {
        guard let latest else { return "—" }
        return "\(latest.partial ? "≥ " : "")\(format(latest.bytes))"
    }

    func caption(now: Date, calendar: Calendar, format: (Int64) -> String) -> String {
        switch change(now: now, calendar: calendar) {
        case .tracking: return "Tracking from today"
        case .partial: return "Some folders could not be read"
        case let .since(label, delta):
            if abs(delta) < Self.noChangeBytes { return "No change since \(label)" }
            return "\(delta > 0 ? "+" : "−")\(format(abs(delta))) since \(label)"
        }
    }
}
