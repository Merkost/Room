import Foundation
import RoomCore

/// Reads legacy preferences until a control writes its replacement key.
nonisolated enum RoomMenuBarSettings {
    static let valueKey = "RoomMenuBarValue"
    static let legacyMetricKey = "RoomMenuBarMetric"
    static let iconKey = "RoomMenuBarIcon"
    static let tintOnlyWhenNeededKey = "RoomMenuBarTintOnlyWhenNeeded"
    static let goalBytesKey = "RoomGoalBytes"
    static let showSwapDefault = false
    static let showSwapKey = "RoomMonitorShowSwap"

    static let defaultGoalBytes: Int64 = 50_000_000_000
    static let minimumGoalBytes: Int64 = 20_000_000_000
    static let maximumGoalBytes: Int64 = 200_000_000_000
    static let goalStepBytes: Int64 = 10_000_000_000

    static func clampGoalBytes(_ bytes: Int64) -> Int64 {
        min(maximumGoalBytes, max(minimumGoalBytes, bytes))
    }

    static func goalBytes(in defaults: UserDefaults) -> Int64 {
        let stored = (defaults.object(forKey: goalBytesKey) as? NSNumber)?.int64Value ?? defaultGoalBytes
        return clampGoalBytes(stored)
    }

    static func steppedGoalBytes(from bytes: Int64, by steps: Int) -> Int64 {
        // More than the entire range of steps always reaches an endpoint.
        // Bound before multiplication so even Int.min/max cannot overflow.
        let rangeSteps = Int((maximumGoalBytes - minimumGoalBytes) / goalStepBytes)
        let boundedSteps = min(rangeSteps, max(-rangeSteps, steps))
        return clampGoalBytes(clampGoalBytes(bytes) + Int64(boundedSteps) * goalStepBytes)
    }

    static func setGoalBytes(_ bytes: Int64, in defaults: UserDefaults) {
        defaults.set(clampGoalBytes(bytes), forKey: goalBytesKey)
    }

    static func canSelectValue(_ candidate: RoomMenuBarValueMode, icon: RoomMenuBarIconMode) -> Bool {
        candidate != .none || icon != .none
    }

    static func canSelectIcon(_ candidate: RoomMenuBarIconMode, value: RoomMenuBarValueMode) -> Bool {
        candidate != .none || value != .none
    }

    static func setValue(_ value: RoomMenuBarValueMode, in defaults: UserDefaults) {
        let current = makeInput(defaults: defaults, memoryReport: nil, diskCapacityBytes: 0, diskAvailableBytes: 0)
        guard canSelectValue(value, icon: current.icon) else { return }
        defaults.set(value.rawValue, forKey: valueKey)
    }

    static func setIcon(_ icon: RoomMenuBarIconMode, in defaults: UserDefaults) {
        let current = makeInput(defaults: defaults, memoryReport: nil, diskCapacityBytes: 0, diskAvailableBytes: 0)
        guard canSelectIcon(icon, value: current.value) else { return }
        defaults.set(icon.rawValue, forKey: iconKey)
    }

    static func showSwap(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showSwapKey) as? Bool ?? showSwapDefault
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
            icon: defaults.string(forKey: iconKey).flatMap(RoomMenuBarIconMode.init(rawValue:)) ?? .symbol,
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
