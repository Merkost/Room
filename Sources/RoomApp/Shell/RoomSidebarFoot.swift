import Foundation

/// The sidebar foot: "312 GB free" + used minibar; below goal the figure is elevated + semibold + half pocket.
nonisolated struct RoomSidebarFoot: Equatable, Sendable {
    let freeText: String?          // nil = capacity unreadable: the foot shows nothing rather than an old figure
    let volumeName: String?        // URLResourceKey.volumeLocalizedNameKey, never invented
    let usedFraction: Double?      // minibar fill; nil when unreadable
    let belowGoal: Bool
    let accessibilityLabel: String

    static func make(capacityBytes: Int64?, freeBytes: Int64?, goalBytes: Int64?, volumeName: String?,
                     hidden: Bool, format: (Int64) -> String) -> RoomSidebarFoot {
        guard let capacity = capacityBytes, let free = freeBytes, capacity > 0, free >= 0, free <= capacity else {
            return .init(freeText: nil, volumeName: nil, usedFraction: nil, belowGoal: false,
                         accessibilityLabel: "Free space unavailable")
        }
        let below = goalBytes.map { free < $0 } ?? false
        let shown = hidden ? String(format(free).map { $0.isNumber ? "•" : $0 }) : format(free)
        var spoken = [volumeName, hidden ? "free space hidden" : "\(format(free)) free"].compactMap { $0 }.joined(separator: ", ")
        if below, let goal = goalBytes {
            spoken += hidden ? ", under your goal" : ", \(format(goal - free)) under your goal"
        }
        return .init(freeText: "\(shown) free", volumeName: volumeName,
                     usedFraction: Double(capacity - free) / Double(capacity), belowGoal: below,
                     accessibilityLabel: spoken)
    }
}
