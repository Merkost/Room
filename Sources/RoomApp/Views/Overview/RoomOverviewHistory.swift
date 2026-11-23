import Foundation
import RoomCore

nonisolated enum RoomOverviewHistoryRange: String, CaseIterable, Sendable {
    case day, week, twelveWeeks

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .twelveWeeks: "12 weeks"
        }
    }

    func label(at date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.hour().minute())
        case .week: date.formatted(.dateTime.weekday(.abbreviated))
        case .twelveWeeks: date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

nonisolated enum RoomOverviewHistoryMetric: String, CaseIterable, Sendable {
    case change, freeSpace

    var title: String { self == .change ? "Change" : "Free space" }
}

nonisolated struct RoomOverviewHistoryPoint: Identifiable, Equatable, Sendable {
    let id: Int
    let bucket: Date
    let sample: RoomVolumeSample?
    let usedChange: Int64?
    let run: Int

    func value(for metric: RoomOverviewHistoryMetric) -> Int64? {
        switch metric {
        case .freeSpace: sample?.freeBytes
        case .change: usedChange
        }
    }
}

nonisolated struct RoomOverviewHistory: Equatable, Sendable {
    let points: [RoomOverviewHistoryPoint]

    init(log: RoomVolumeSampleLog, range: RoomOverviewHistoryRange, now: Date, calendar: Calendar) {
        let inputs: [(bucket: Date, sample: RoomVolumeSample?)]
        switch range {
        case .day:
            let start = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            inputs = (0...24).reversed().map { offset in
                let at = start.addingTimeInterval(-Double(offset) * 3_600)
                return (at, log.hourly.last {
                    $0.at <= now && calendar.dateInterval(of: .hour, for: $0.at)?.start == at
                })
            }
        case .week:
            let start = RoomSizeLog.weekStart(containing: now, calendar: calendar)
            inputs = (-1...6).map { offset in
                let at = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                return (at, log.daily.last { $0.at <= now && calendar.isDate($0.at, inSameDayAs: at) })
            }
        case .twelveWeeks:
            let start = RoomSizeLog.weekStart(containing: now, calendar: calendar)
            let previous = zip((1...12).reversed(), log.pastWeeks(12, now: now, calendar: calendar))
            inputs = previous.map { offset, value in
                let at = calendar.date(byAdding: .weekOfYear, value: -offset, to: start) ?? start
                return (at, value?.last)
            } + [(start, log.weekly.last { $0.weekStart == start && $0.last.at <= now }?.last)]
        }

        var run = 0
        points = zip(inputs, inputs.dropFirst()).enumerated().map { index, pair in
            let (previous, current) = pair
            var change: Int64?
            if let sample = current.sample, let before = previous.sample, sample.sameVolume(as: before) {
                change = before.freeBytes - sample.freeBytes
            } else {
                run += 1
            }
            return RoomOverviewHistoryPoint(id: index, bucket: current.bucket, sample: current.sample,
                                            usedChange: change, run: run)
        }
    }

    func latest(for metric: RoomOverviewHistoryMetric) -> RoomOverviewHistoryPoint? {
        points.last { $0.value(for: metric) != nil }
    }

    /// Forecast only over a complete 12-week series from one known volume.
    func monthsUntilGoal(_ goal: Int64?) -> Int? {
        guard let goal, points.count == 12,
              let first = points.first?.sample, let last = points.last?.sample,
              last.freeBytes > goal,
              points.allSatisfy({ $0.sample?.sameVolume(as: first) == true }),
              let firstBucket = points.first?.bucket, let lastBucket = points.last?.bucket else { return nil }
        let elapsedWeeks = lastBucket.timeIntervalSince(firstBucket) / (7 * 86_400)
        guard elapsedWeeks > 0 else { return nil }
        let rate = Double(first.freeBytes - last.freeBytes) / elapsedWeeks
        guard rate >= 500_000_000 else { return nil }
        let months = Double(last.freeBytes - goal) / rate / (365.25 / 12 / 7)
        guard (1...60).contains(months) else { return nil }
        return Int(months.rounded())
    }
}

nonisolated struct RoomOverviewHistoryGrowth: Equatable, Sendable {
    let name: String
    let bytes: Int64
    let measuredAt: Date

    static func between(_ earlier: RoomStoredTree?, _ current: RoomStoredTree?, volume: String?,
                        now: Date, calendar: Calendar) -> Self? {
        guard let earlier, let current, let volume,
              !earlier.isPartial, !current.isPartial, earlier.rootID == current.rootID,
              earlier.volumeUUID == volume, current.volumeUUID == volume else { return nil }
        let monday = RoomSizeLog.weekStart(containing: now, calendar: calendar)
        guard let floor = calendar.date(byAdding: .day, value: -7, to: monday),
              (floor...monday).contains(earlier.scannedAt),
              current.scannedAt >= monday, current.scannedAt > earlier.scannedAt,
              current.scannedAt <= now else { return nil }

        func indexedFolders(_ node: RoomTreeNode) -> [String: RoomTreeNode] {
            var index: [String: RoomTreeNode] = [:]
            func visit(_ parent: RoomTreeNode) {
                for folder in parent.children where folder.isDirectory && !folder.isPartial {
                    index[folder.relativePath] = folder
                    visit(folder)
                }
            }
            visit(node)
            return index
        }

        let old = indexedFolders(earlier.tree)
        let new = indexedFolders(current.tree)
        let changes = new.compactMap { path, folder -> (path: String, name: String, bytes: Int64)? in
            guard let before = old[path], before.allocatedBytes >= 0,
                  folder.allocatedBytes > before.allocatedBytes else { return nil }
            return (path, folder.name, folder.allocatedBytes - before.allocatedBytes)
        }
        let winner = changes.sorted {
            if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
            return $0.path < $1.path
        }.first
        return winner.map { Self(name: $0.name, bytes: $0.bytes, measuredAt: current.scannedAt) }
    }
}
