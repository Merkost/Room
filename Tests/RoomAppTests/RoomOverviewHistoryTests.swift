import Foundation
import RoomCore
import Testing
@testable import RoomApp

struct RoomOverviewHistoryTests {
    let gb: Int64 = 1_000_000_000
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func record(_ log: inout RoomVolumeSampleLog, at date: Date, free: Int64, volume: String? = "disk") {
        log.record(.init(at: date, capacityBytes: 500 * gb, freeBytes: free * gb, volumeID: volume), calendar: calendar)
    }

    @Test func sixPresentationsUseTheSameMeasuredValues() throws {
        var log = RoomVolumeSampleLog()
        record(&log, at: date(15), free: 89)
        record(&log, at: date(16), free: 86)
        record(&log, at: date(17, hour: 11), free: 83)
        record(&log, at: date(17), free: 85)

        let day = RoomOverviewHistory(log: log, range: .day, now: date(17), calendar: calendar)
        #expect(day.points.count == 24)
        #expect(day.latest(for: .change)?.usedChange == -2 * gb)
        #expect(day.latest(for: .freeSpace)?.sample?.freeBytes == 85 * gb)
        let week = RoomOverviewHistory(log: log, range: .week, now: date(17), calendar: calendar)
        #expect(week.points.count == 7)
        #expect(week.points.map(\.usedChange) == [3 * gb, gb, nil, nil, nil, nil, nil])
        #expect(week.latest(for: .freeSpace)?.sample?.freeBytes == 85 * gb)
        let quarter = RoomOverviewHistory(log: log, range: .twelveWeeks, now: date(17), calendar: calendar)
        #expect(quarter.points.count == 12)
        #expect(quarter.latest(for: .change)?.usedChange == 4 * gb)
        #expect(quarter.latest(for: .freeSpace)?.sample?.freeBytes == 85 * gb)
    }

    @Test func gapsAndVolumeChangesBreakComparisonsAndLines() throws {
        var log = RoomVolumeSampleLog()
        record(&log, at: date(16), free: 100)
        record(&log, at: date(18), free: 80)
        record(&log, at: date(19), free: 75, volume: "another disk")
        record(&log, at: date(20), free: 70, volume: nil)
        let week = RoomOverviewHistory(log: log, range: .week, now: date(20), calendar: calendar)
        #expect(week.points[1].sample == nil)
        #expect(week.points[2].run != week.points[0].run)
        #expect(week.points[3].run != week.points[2].run)
        #expect(week.points[4].run != week.points[3].run)
        #expect(week.latest(for: .change) == nil)
        #expect(week.latest(for: .freeSpace)?.sample?.freeBytes == 70 * gb)
    }

    @Test func forecastRequiresTwelveComparableWeeksAndASignificantDecline() {
        var log = RoomVolumeSampleLog()
        let now = date(18)
        for index in 0..<12 {
            let sampleDate = now.addingTimeInterval(Double(index - 11) * 7 * 86_400)
            record(&log, at: sampleDate, free: 110 - Int64(index) * 2)
        }
        let history = RoomOverviewHistory(log: log, range: .twelveWeeks, now: now, calendar: calendar)
        #expect(history.monthsUntilGoal(50 * gb) == 4)
        #expect(history.monthsUntilGoal(90 * gb) == nil)
        var sparse = RoomVolumeSampleLog()
        record(&sparse, at: now.addingTimeInterval(-77 * 86_400), free: 110)
        record(&sparse, at: now, free: 88)
        #expect(RoomOverviewHistory(log: sparse, range: .twelveWeeks, now: now, calendar: calendar)
            .monthsUntilGoal(50 * gb) == nil)
    }

    @Test func attributionRequiresTwoCompleteComparableMapsAndAKnownFolder() {
        func map(_ when: Date, bytes: Int64, root: String = "home", partial: Bool = false) -> RoomStoredTree {
            let folder = RoomTreeNode(name: "Build artifacts", relativePath: "Build artifacts",
                allocatedBytes: bytes, fileCount: 1, kindBytes: [:], isPartial: false, isDirectory: true,
                children: [], other: nil)
            let top = RoomTreeNode(name: "Home", relativePath: "", allocatedBytes: bytes, fileCount: 1,
                kindBytes: [:], isPartial: partial, isDirectory: true, children: [folder], other: nil)
            return RoomStoredTree(rootID: root, displayPath: "~", scannedAt: when, cancelled: false,
                volumeUUID: "disk", issueCount: 0, tree: top)
        }
        let lastWeek = map(date(15), bytes: 3 * gb)
        let new = map(date(17), bytes: 10 * gb)
        let growth = RoomOverviewHistoryGrowth.between(lastWeek, new, volume: "disk", now: date(18), calendar: calendar)
        #expect(growth?.name == "Build artifacts" && growth?.bytes == 7 * gb)
        #expect(RoomOverviewHistoryGrowth.between(map(date(8), bytes: gb), new, volume: "disk",
            now: date(18), calendar: calendar) == nil)
        #expect(RoomOverviewHistoryGrowth.between(lastWeek, map(date(17), bytes: 10 * gb, root: "other"),
            volume: "disk", now: date(18), calendar: calendar) == nil)
        #expect(RoomOverviewHistoryGrowth.between(lastWeek, map(date(17), bytes: 10 * gb, partial: true),
            volume: "disk", now: date(18), calendar: calendar) == nil)
    }
}
