import Foundation
import Observation

/// Keeps the last completed scan separate from the in-progress Caches review.
@Observable @MainActor
final class RoomCachesCheckStore {
    private(set) var check: RoomCachesCheck?
    private(set) var invalidatedAt: Date?
    private static let invalidationKey = "RoomOverviewCachesInvalidatedAt"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        invalidatedAt = defaults.object(forKey: Self.invalidationKey) as? Date
        if let at = defaults.object(forKey: "RoomLastCachesCheckAt") as? Date,
           let bytes = defaults.object(forKey: "RoomLastCachesCheckBytes") as? NSNumber,
           let partial = defaults.object(forKey: "RoomLastCachesCheckPartial") as? Bool {
            check = RoomCachesCheck(at: at, bytes: bytes.int64Value, partial: partial)
        }
    }

    func invalidate(at date: Date) {
        let latest = max(invalidatedAt ?? date, date)
        defaults.set(latest, forKey: Self.invalidationKey)
        invalidatedAt = latest
    }

    func save(_ check: RoomCachesCheck) {
        defaults.set(check.bytes, forKey: "RoomLastCachesCheckBytes")
        defaults.set(check.partial, forKey: "RoomLastCachesCheckPartial")
        defaults.set(check.at, forKey: "RoomLastCachesCheckAt")
        self.check = check
    }
}
