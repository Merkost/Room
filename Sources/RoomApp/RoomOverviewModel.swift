import Foundation
import Observation

@Observable @MainActor
final class RoomOverviewModel {
    private(set) var snapshot: RoomOverviewSnapshot
    private(set) var greeting: String
    private(set) var cacheCaption: String?
    private(set) var nextCacheUpdateAt: Date?
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        let date = now()
        snapshot = Self.makeSnapshot(capacity: nil, goalBytes: nil, now: date)
        greeting = Self.greeting(at: date)
    }

    func update(capacity: RoomVolumeCapacity?, goalBytes: Int64?, caches: RoomCachesCheck? = nil,
                invalidatedAt: Date? = nil, calendar: Calendar = .current,
                homeKinds: RoomHomeKinds? = nil, mapActionAvailable: Bool = false,
                mapping: RoomOverviewMapping? = nil, stoppedMapping: Bool = false) {
        let date = now()
        let next = Self.makeSnapshot(capacity: capacity, goalBytes: goalBytes, caches: caches,
                                     invalidatedAt: invalidatedAt, now: date, homeKinds: homeKinds,
                                     mapActionAvailable: mapActionAvailable, mapping: mapping, stoppedMapping: stoppedMapping)
        if snapshot != next { snapshot = next }
        let nextGreeting = Self.greeting(at: date, calendar: calendar)
        if greeting != nextGreeting { greeting = nextGreeting }

        let checkedAt = next.cachesCheckedAt
        let caption = checkedAt == nil ? nil : caches?.caption(now: date, calendar: calendar)
        let nextUpdate: Date? = checkedAt.flatMap {
            [
                $0.addingTimeInterval(60),
                $0.addingTimeInterval(RoomOverviewSnapshot.cacheFreshness),
                calendar.dateInterval(of: .day, for: date)?.end,
            ].compactMap { $0 }.filter { $0 > date }.min()
        }
        if cacheCaption != caption { cacheCaption = caption }
        if nextCacheUpdateAt != nextUpdate { nextCacheUpdateAt = nextUpdate }
    }

    private static func makeSnapshot(capacity: RoomVolumeCapacity?, goalBytes: Int64?, caches: RoomCachesCheck? = nil,
                                     invalidatedAt: Date? = nil, now: Date, homeKinds: RoomHomeKinds? = nil,
                                     mapActionAvailable: Bool = false, mapping: RoomOverviewMapping? = nil,
                                     stoppedMapping: Bool = false) -> RoomOverviewSnapshot {
        RoomOverviewSnapshot.make(.init(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes,
            goalBytes: goalBytes.map(RoomMenuBarSettings.clampGoalBytes), caches: caches, cachesInvalidatedAt: invalidatedAt,
            now: now, hidden: false, homeKinds: homeKinds, mapActionAvailable: mapActionAvailable,
            mapping: mapping, stoppedMapping: stoppedMapping), format: RoomFormat.overviewBytes)
    }

    private static func greeting(at date: Date, calendar: Calendar = .current) -> String {
        RoomOverviewCopy.greeting(hour: calendar.component(.hour, from: date))
    }
}
