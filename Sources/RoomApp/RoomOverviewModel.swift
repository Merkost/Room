import Foundation
import Observation

@Observable @MainActor
final class RoomOverviewModel {
    private(set) var snapshot: RoomOverviewSnapshot
    private(set) var greeting: String
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        let date = now()
        snapshot = Self.makeSnapshot(capacity: nil, goalBytes: nil, now: date)
        greeting = Self.greeting(at: date)
    }

    func update(capacity: RoomVolumeCapacity?, goalBytes: Int64?) {
        let date = now()
        let next = Self.makeSnapshot(capacity: capacity, goalBytes: goalBytes, now: date)
        if snapshot != next { snapshot = next }
        let nextGreeting = Self.greeting(at: date)
        if greeting != nextGreeting { greeting = nextGreeting }
    }

    private static func makeSnapshot(capacity: RoomVolumeCapacity?, goalBytes: Int64?, now: Date) -> RoomOverviewSnapshot {
        RoomOverviewSnapshot.make(.init(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes,
            goalBytes: goalBytes.map(RoomMenuBarSettings.clampGoalBytes), caches: nil, cachesInvalidatedAt: nil,
            now: now, hidden: false), format: RoomFormat.overviewBytes)
    }

    private static func greeting(at date: Date) -> String {
        RoomOverviewCopy.greeting(hour: Calendar.current.component(.hour, from: date))
    }
}
