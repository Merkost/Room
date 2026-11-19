import Foundation

nonisolated enum RoomMadeRoom {
    nonisolated struct Summary: Equatable, Sendable {
        let bytes: Int64
        let count: Int
        let since: Date
        let sinceMonth: String

        var caption: String {
            RoomSignature.moved(bytes: bytes, cleanups: count, since: since).caption(month: sinceMonth) ?? ""
        }
    }

    static func summary(activities: [RoomActivity], calendar: Calendar = .current) -> Summary? {
        let kept = activities.filter { $0.restoredCount == 0 && $0.errorCount == 0 }
        let bytes = kept.reduce(Int64(0)) { total, activity in
            let (sum, overflow) = total.addingReportingOverflow(max(0, activity.bytes))
            return overflow ? .max : sum
        }
        guard bytes > 0, let since = kept.map(\.date).min() else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return Summary(bytes: bytes, count: kept.count,
            since: since, sinceMonth: formatter.string(from: since))
    }
}
