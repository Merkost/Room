import Foundation

nonisolated enum RoomMadeRoom {
    nonisolated struct Summary: Equatable, Sendable {
        let bytes: Int64
        let count: Int
        let since: Date
        let sinceMonth: String

        var caption: String {
            "of room made since \(sinceMonth), across \(count) \(count == 1 ? "cleanup" : "cleanups")"
        }
    }

    static func summary(activities: [RoomActivity], calendar: Calendar = .current) -> Summary? {
        let kept = activities.filter { $0.restoredCount == 0 && $0.errorCount == 0 }
        guard let since = kept.map(\.date).min() else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return Summary(bytes: kept.reduce(0) { $0 + $1.bytes }, count: kept.count,
            since: since, sinceMonth: formatter.string(from: since))
    }
}
