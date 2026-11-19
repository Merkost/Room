import Foundation
import Testing
@testable import RoomApp

struct RoomVolumeHistoryTests {
    let gb: Int64 = 1_000_000_000

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func sample(_ at: Date, free: Int64, capacity: Int64 = 994_000_000_000, volume: String? = "A") -> RoomVolumeSample {
        RoomVolumeSample(at: at, capacityBytes: capacity, freeBytes: free * gb, volumeID: volume)
    }

    @Test func samplingTriggersAndRetention() {
        var log = RoomVolumeSampleLog()
        #expect(log.shouldRecord(.monitorTick, now: date(19, 11), calendar: calendar))
        log.record(sample(date(19, 11, 4), free: 312), calendar: calendar)
        #expect(!log.shouldRecord(.monitorTick, now: date(19, 11, 40), calendar: calendar))
        #expect(log.shouldRecord(.monitorTick, now: date(19, 12), calendar: calendar))
        #expect(log.shouldRecord(.scanCompleted, now: date(19, 11, 20), calendar: calendar))
        #expect(!log.shouldRecord(.scanCompleted, now: date(19, 10), calendar: calendar))
        #expect(!log.shouldRecord(.activation, now: date(19, 11, 50), calendar: calendar))
        #expect(log.shouldRecord(.activation, now: date(19, 12), calendar: calendar))
        #expect(!log.record(sample(date(19, 12), free: 1_000), calendar: calendar))
        #expect(log.record(sample(date(19, 12), free: 311), calendar: calendar))
        #expect(!log.record(sample(date(19, 12, 59), free: 309), calendar: calendar))
        #expect(log.latest?.freeBytes == 309 * gb)

        var hourly = RoomVolumeSampleLog()
        for hour in 0..<60 {
            hourly.record(sample(date(16, 0).addingTimeInterval(Double(hour * 3600)), free: 300), calendar: calendar)
        }
        #expect(hourly.hourly.count == 49)
        var years = RoomVolumeSampleLog()
        for week in 0..<110 {
            years.record(sample(date(19).addingTimeInterval(Double(week * 7 * 86_400)), free: 300), calendar: calendar)
        }
        #expect(years.weekly.count == 105)
    }

    @Test func weeklyBaselineKeepsUnknownDaysAndRejectsOtherVolumes() {
        var log = RoomVolumeSampleLog()
        log.record(sample(date(13), free: 330), calendar: calendar)
        log.record(sample(date(15), free: 322), calendar: calendar)
        log.record(sample(date(17), free: 318), calendar: calendar)
        log.record(sample(date(19, 11), free: 312), calendar: calendar)
        #expect(log.change(now: date(19), calendar: calendar) == .since(label: "Monday", usedBytes: 10 * gb))
        let week = log.days(inWeekContaining: date(19), calendar: calendar)
        #expect(week.map { $0?.freeBytes } == [nil, 318 * gb, nil, 312 * gb, nil, nil, nil])
        let past = log.pastWeeks(3, now: date(19), calendar: calendar)
        #expect(past.map { $0?.last.freeBytes } == [nil, nil, 322 * gb])
        log.record(sample(date(19), free: 312, volume: "B"), calendar: calendar)
        #expect(log.change(now: date(19), calendar: calendar) == .volumeChanged)

        var recent = RoomVolumeSampleLog()
        recent.record(sample(date(6), free: 340), calendar: calendar)
        recent.record(sample(date(18), free: 320), calendar: calendar)
        #expect(recent.change(now: date(18), calendar: calendar) == .tracking)
        recent.record(sample(date(19), free: 315), calendar: calendar)
        #expect(recent.change(now: date(19), calendar: calendar) == .since(label: "Wednesday", usedBytes: 5 * gb))
    }

    @Test func kindsNeedACompleteMatchingMeasurement() {
        var log = RoomVolumeSampleLog()
        log.record(sample(date(19), free: 315), calendar: calendar)
        log.recordKinds(["developer": 55], at: date(19), complete: false, volumeID: "A", calendar: calendar)
        log.recordKinds(["developer": 80], at: date(19), complete: true, volumeID: "B", calendar: calendar)
        #expect(log.weekly.last?.kindBytes == nil)
        log.recordKinds(["developer": 90], at: date(19), complete: true, volumeID: "A", calendar: calendar)
        #expect(log.weekly.last?.kindBytes == ["developer": 90])
    }

    @Test func fallbackDSTWeekStartsAtLocalMonday() throws {
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 18)))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        #expect(RoomSizeLog.weekStart(containing: sunday, calendar: calendar) == monday)
        var log = RoomVolumeSampleLog()
        log.record(sample(sunday, free: 315), calendar: calendar)
        #expect(log.days(inWeekContaining: sunday, calendar: calendar)[6]?.freeBytes == 315 * gb)
    }
}

@Suite @MainActor
struct RoomVolumeHistoryPersistenceTests {
    @Test func writesOnlyOnBucketRoll() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomStateStore(directory: directory)
        let writer = RoomStateWriter(store: store, debounce: .seconds(60))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestVolumeClock(start)
        let history = RoomVolumeHistory(writer: writer, now: { clock.now })
        let first = try #require(RoomVolumeCapacity(capacityBytes: 100, freeBytes: 40))
        let later = try #require(RoomVolumeCapacity(capacityBytes: 100, freeBytes: 39))
        await history.waitForLoad()
        history.record(first, volumeID: "A", trigger: .launch)
        await writer.flush(deadline: .seconds(5))
        #expect(!writer.hasPendingWrites)
        clock.now = start.addingTimeInterval(20)
        history.record(later, volumeID: "A", trigger: .monitorTick)
        #expect(history.log.latest?.freeBytes == 40)
        #expect(!writer.hasPendingWrites)
        clock.now = start.addingTimeInterval(3600)
        history.record(later, volumeID: "A", trigger: .monitorTick)
        #expect(writer.hasPendingWrites)
        await writer.flush(deadline: .seconds(5))
        #expect(await store.load(RoomVolumeSampleLog.self, from: .volumeSamples).value?.latest?.freeBytes == 39)
    }

    @Test func terminateFlushesCurrentHour() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomStateStore(directory: directory)
        let writer = RoomStateWriter(store: store)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestVolumeClock(start)
        let history = RoomVolumeHistory(writer: writer, now: { clock.now })
        let first = try #require(RoomVolumeCapacity(capacityBytes: 100, freeBytes: 40))
        let later = try #require(RoomVolumeCapacity(capacityBytes: 100, freeBytes: 39))
        await history.waitForLoad()
        history.record(first, volumeID: "A", trigger: .launch)
        await writer.flush(deadline: .seconds(5))
        clock.now = start.addingTimeInterval(20)
        history.record(later, volumeID: "A", trigger: .scanCompleted)
        #expect(history.log.latest?.freeBytes == 39 && !writer.hasPendingWrites)
        history.prepareForTermination()
        await writer.flush(deadline: .seconds(5))
        #expect(await store.load(RoomVolumeSampleLog.self, from: .volumeSamples).value?.latest?.freeBytes == 39)
    }
}

@MainActor private final class TestVolumeClock {
    var now: Date
    init(_ date: Date) { now = date }
}
