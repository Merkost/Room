#if !ROOM_APP_STORE
import Foundation

/// PE-28 weekly gentle check, Direct only (D-11). Compares two read-only Quick checks a week apart.
nonisolated struct RoomWeeklyCheckRecord: Codable, Equatable, Sendable {
    var at: Date
    var eligibleBytes: Int64
    var partial: Bool
    var scope: String               // "quick"; a different scope is never compared
}

nonisolated enum RoomWeeklyCheck {
    static let defaultThresholdBytes: Int64 = 5_000_000_000
    static let thresholdRangeGB = 1...50
    static let minimumGap: TimeInterval = 6 * 24 * 3600      // interval 7 days, tolerance 1 day

    /// Growth to report, or nil. Only two complete Quick checks 6–14 days apart are compared: a partial check is a
    /// lower bound and could overstate (previous partial) or hide (current partial) growth, so neither notifies.
    static func growthToReport(previous: RoomWeeklyCheckRecord?, current: RoomWeeklyCheckRecord,
                               thresholdBytes: Int64) -> Int64? {
        guard let previous, !previous.partial, !current.partial, previous.scope == current.scope,
              current.eligibleBytes >= 0, previous.eligibleBytes >= 0 else { return nil }
        let gap = current.at.timeIntervalSince(previous.at)
        guard gap >= minimumGap, gap <= 14 * 24 * 3600 else { return nil }
        let growth = current.eligibleBytes - previous.eligibleBytes
        return growth >= max(1, thresholdBytes) ? growth : nil
    }
    /// The record kept for next week: a complete check replaces it; a partial one never does.
    static func nextRecord(previous: RoomWeeklyCheckRecord?, current: RoomWeeklyCheckRecord) -> RoomWeeklyCheckRecord? {
        current.partial ? previous : current
    }
}
#endif
