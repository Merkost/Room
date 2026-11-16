import Foundation
import RoomCore

/// Reads the menu bar preferences without migrating or writing stored values.
nonisolated enum RoomMenuBarSettings {
    static let valueKey = "RoomMenuBarValue"
    static let legacyMetricKey = "RoomMenuBarMetric"
    static let iconKey = "RoomMenuBarIcon"
    static let tintOnlyWhenNeededKey = "RoomMenuBarTintOnlyWhenNeeded"
    static let goalBytesKey = "RoomGoalBytes"
    static let showSwapKey = "RoomMonitorShowSwap"

    static let defaultGoalBytes: Int64 = 50_000_000_000
    static let minimumGoalBytes: Int64 = 20_000_000_000
    static let maximumGoalBytes: Int64 = 200_000_000_000

    static func goalBytes(in defaults: UserDefaults) -> Int64 {
        let stored = (defaults.object(forKey: goalBytesKey) as? NSNumber)?.int64Value ?? defaultGoalBytes
        return min(maximumGoalBytes, max(minimumGoalBytes, stored))
    }

    static func showSwap(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showSwapKey) as? Bool ?? false
    }

    static func makeInput(defaults: UserDefaults, memoryReport: MemoryReport?,
                          diskCapacityBytes: Int64, diskAvailableBytes: Int64) -> RoomMenuBarInput {
        let value: RoomMenuBarValueMode
        if defaults.object(forKey: valueKey) != nil {
            value = defaults.string(forKey: valueKey).flatMap(RoomMenuBarValueMode.init(rawValue:)) ?? .memory
        } else {
            value = defaults.string(forKey: legacyMetricKey) == "storage" ? .disk : .memory
        }

        var input = RoomMenuBarInput(
            value: value,
            icon: defaults.string(forKey: iconKey).flatMap(RoomMenuBarIconMode.init(rawValue:)) ?? .mark,
            tintOnlyWhenNeeded: defaults.object(forKey: tintOnlyWhenNeededKey) as? Bool ?? true,
            goalBytes: goalBytes(in: defaults))

        if let report = memoryReport, report.totalBytes > 0,
           report.usedBytes > 0 || report.availableBytes > 0 {
            input.memoryUsedBytes = max(0, min(report.totalBytes, report.usedBytes))
            input.memoryTotalBytes = report.totalBytes
            input.pressure = switch report.pressure {
            case .unknown: .unknown
            case .normal: .normal
            case .elevated: .elevated
            case .critical: .critical
            }
        }
        if diskCapacityBytes > 0 {
            input.diskFreeBytes = max(0, min(diskCapacityBytes, diskAvailableBytes))
        }
        return input
    }
}
