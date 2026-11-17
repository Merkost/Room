import Foundation

/// Settings previews keep the person's choices while using fixed sample measurements.
nonisolated enum RoomMenuBarPreviewScenarios {
    static func inputs(from input: RoomMenuBarInput) -> (normal: RoomMenuBarInput, elevated: RoomMenuBarInput) {
        var normal = input
        normal.memoryUsedBytes = 16_200_000_000
        normal.memoryTotalBytes = 32_000_000_000
        normal.pressure = .normal
        normal.diskFreeBytes = 312_000_000_000

        var elevated = input
        elevated.memoryUsedBytes = 24_800_000_000
        elevated.memoryTotalBytes = 32_000_000_000
        elevated.pressure = .elevated
        // Compare before subtracting so a malformed saved goal cannot overflow.
        elevated.diskFreeBytes = input.goalBytes > 10_000_000_000
            ? input.goalBytes - 9_000_000_000 : 1_000_000_000
        return (normal, elevated)
    }
}
