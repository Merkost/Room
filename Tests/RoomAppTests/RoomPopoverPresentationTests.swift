import Foundation
import Testing
@testable import RoomApp

@Suite("Popover presentation")
struct RoomPopoverPresentationTests {
    private let gb: Int64 = 1_000_000_000
    private let format = RoomMenuBarFormat.fixtureGigabytes
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }
    private var now: Date { date(2026, 11, 17, 10) }
    private var pinned: RoomPinnedRoom {
        RoomPinnedRoom(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                       accessFolderID: "work", name: "Work", order: 0)
    }
    private var input: RoomMenuBarInput {
        RoomMenuBarInput(value: .both, memoryUsedBytes: 16_200_000_000,
                        memoryTotalBytes: 32 * gb, pressure: .normal,
                        diskFreeBytes: 312 * gb, goalBytes: 50 * gb)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func size(_ bytes: Int64) -> String {
        bytes >= gb ? format.memory(bytes) : String(format: "%.0f MB", Double(bytes) / 1e6)
    }

    private func log(_ entries: [(Date, Int64, Bool)]) -> RoomSizeLog {
        var log = RoomSizeLog()
        for (at, bytes, partial) in entries {
            log.record(RoomSizePoint(at: at, bytes: bytes, partial: partial), calendar: calendar)
        }
        return log
    }

    private func make(input: RoomMenuBarInput? = nil, capacity: Int64 = 994_000_000_000,
                      swap: Int64? = nil, showSwap: Bool = false,
                      caches: RoomCachesCheck? = nil, room: RoomRoomsModel.State = .empty) -> RoomPopoverPresentation {
        RoomPopoverPresentation.make(input: input ?? self.input, diskCapacityBytes: capacity,
                                     swapBytes: swap, showSwap: showSwap, caches: caches, room: room,
                                     now: now, calendar: calendar, format: format, formatSize: size)
    }

    @Test func fixtureContainsExactlyTheSixteenApplicableStrings() {
        let history = log([(date(2026, 11, 15, 20), 71_100_000_000, false),
                           (date(2026, 11, 17, 9), 74_300_000_000, false)])
        let output = make(caches: RoomCachesCheck(at: date(2026, 11, 16, 9), bytes: 8_400_000_000, partial: false),
                          room: .measured(pinned, history))
        #expect(output.strings == [
            "Room", "Settings", "312 GB free", "of 994 GB", "Goal: keep 50 GB free",
            "16.2 GB", "of 32 GB memory", "Normal", "8.4 GB of caches can go",
            "Checked yesterday", "Open Caches", "Work", "+3.2 GB since Monday", "74.3 GB",
            "Open Room", "Quit"
        ])
    }

    @Test func fixtureCardsHaveTheSpecifiedSpokenLabels() {
        let history = log([(date(2026, 11, 15, 20), 71_100_000_000, false),
                           (date(2026, 11, 17, 9), 74_300_000_000, false)])
        let output = make(caches: RoomCachesCheck(at: date(2026, 11, 16, 9), bytes: 8_400_000_000, partial: false),
                          room: .measured(pinned, history))
        #expect(output.disk.accessibilityLabel == "Free space, 312 gigabytes of 994, goal 50. Open Disk Map.")
        #expect(output.memory.accessibilityLabel == "Memory, 16.2 gigabytes of 32, Normal pressure. Open Memory.")
        #expect(output.caches?.accessibilityLabel == "8.4 gigabytes of caches can go, checked yesterday. Open Caches.")
        #expect(output.room.accessibilityLabel == "Work, 74.3 gigabytes, plus 3.2 gigabytes since Monday. Open in Disk Map.")
    }

    @Test func diskBarFillsUsedSpaceAndPlacesTheGoalAtCapacityMinusGoal() throws {
        let disk = make().disk
        let used = try #require(disk.usedFraction)
        let goal = try #require(disk.goalFraction)
        #expect(abs(used - 682.0 / 994.0) < 1e-12)
        #expect(abs(goal - 944.0 / 994.0) < 1e-12)
        #expect(!disk.belowGoal)
    }

    @Test func belowGoalIsStrictAndTheGoalCanBeUnset() {
        var below = input
        below.diskFreeBytes = 41 * gb
        #expect(make(input: below).disk.belowGoal)
        below.diskFreeBytes = 50 * gb
        #expect(!make(input: below).disk.belowGoal)
        below.goalBytes = 0
        let withoutGoal = make(input: below).disk
        #expect(withoutGoal.goalCaption == nil && withoutGoal.goalFraction == nil && !withoutGoal.belowGoal)
        #expect(withoutGoal.accessibilityLabel == "Free space, 50 gigabytes of 994. Open Disk Map.")
    }

    @Test func diskFractionsClampToTheTrackForOutOfRangeValues() {
        var values = input
        values.diskFreeBytes = -gb
        values.goalBytes = 2_000 * gb
        let low = make(input: values).disk
        #expect(low.value == "0 GB free" && low.usedFraction == 1 && low.goalFraction == 0)
        values.diskFreeBytes = 2_000 * gb
        values.goalBytes = -gb
        let high = make(input: values).disk
        #expect(high.value == "994 GB free" && high.usedFraction == 0)
        #expect(high.goalCaption == nil && high.goalFraction == nil && !high.belowGoal)
    }

    @Test func missingDiskShowsUnavailableAndRetainsOnlyTheKnownGoal() {
        var values = input
        values.diskFreeBytes = nil
        let disk = make(input: values).disk
        #expect(disk.value == "—" && disk.caption == "Free space unavailable")
        #expect(disk.usedFraction == nil && disk.goalFraction == nil && !disk.belowGoal)
        #expect(disk.goalCaption == "Goal: keep 50 GB free")
        #expect(disk.accessibilityLabel == "Free space unavailable. Open Disk Map.")
        #expect(make(capacity: 0).disk.value == "—")
    }

    @Test func missingMemoryNeverBecomesZeroOrShowsPressureOrSwap() {
        var values = input
        values.memoryUsedBytes = nil
        values.pressure = .critical
        let memory = make(input: values, swap: 400_000_000, showSwap: true).memory
        #expect(memory.value == "—" && memory.caption == "Memory measurement unavailable")
        #expect(memory.status == nil && memory.pocketFill == nil && memory.pressure == .unknown)
        #expect(memory.swapCaption == nil)
        #expect(memory.accessibilityLabel == "Memory measurement unavailable. Open Memory.")
        values.memoryUsedBytes = 0
        values.memoryTotalBytes = 0
        #expect(make(input: values).memory.value == "—")
    }

    @Test func unknownPressureKeepsTheMemoryFigureAndOmitsThePocket() {
        var values = input
        values.pressure = .unknown
        let memory = make(input: values).memory
        #expect(memory.value == "16.2 GB" && memory.caption == "of 32 GB memory")
        #expect(memory.status == "—" && memory.pocketFill == nil && memory.pressure == .unknown)
        #expect(memory.accessibilityLabel == "Memory, 16.2 gigabytes of 32, pressure unavailable. Open Memory.")
    }

    @Test(arguments: [(RoomMenuBarPressure.normal, "Normal", 0.0), (.elevated, "Elevated", 0.5), (.critical, "Critical", 1.0)])
    func pressureAlwaysSuppliesTheStatusAndPocketRegardlessOfMenuBarChoices(pressure: RoomMenuBarPressure, status: String, fill: Double) {
        var values = input
        values.value = .none
        values.icon = .none
        values.tintOnlyWhenNeeded = true
        values.pressure = pressure
        let output = make(input: values)
        #expect(output.memory.status == status && output.memory.pocketFill == fill && output.memory.pressure == pressure)
        #expect(output.disk.value == "312 GB free" && output.memory.value == "16.2 GB")
    }

    @Test func swapIsShownOnlyWhenEnabledAndMeasured() {
        let enabled = make(swap: 400_000_000, showSwap: true)
        #expect(enabled.memory.swapCaption == "0.4 GB swap used")
        #expect(enabled.strings.contains("0.4 GB swap used"))
        #expect(make(swap: 400_000_000).memory.swapCaption == nil)
        #expect(make(showSwap: true).memory.swapCaption == nil)
        #expect(make(swap: 0, showSwap: true).memory.swapCaption == "0 GB swap used")
    }

    @Test func memoryValuesClampWithoutTurningMeasuredZeroIntoMissingData() {
        var values = input
        values.memoryUsedBytes = -gb
        #expect(make(input: values).memory.value == "0 GB")
        values.memoryUsedBytes = 40 * gb
        #expect(make(input: values).memory.value == "32 GB")
    }

    @Test func cachesAreOmittedUntilAScanAndRetainPartialAndEmptyResults() {
        #expect(make().caches == nil)
        let partial = make(caches: RoomCachesCheck(at: now, bytes: 8_400_000_000, partial: true)).caches
        #expect(partial?.title == "≥ 8.4 GB of caches can go" && partial?.caption == "Checked just now")
        #expect(partial?.accessory == "Open Caches")
        #expect(partial?.accessibilityLabel == "at least 8.4 gigabytes of caches can go, checked just now. Open Caches.")
        let empty = make(caches: RoomCachesCheck(at: now, bytes: 0, partial: false)).caches
        #expect(empty?.title == "No caches to clear" && empty?.accessory == "Open Caches")
    }

    @Test func emptyMeasuringAndUnavailableRoomsHaveTheirSpecifiedStates() {
        let empty = make().room
        #expect(empty.title == "Pin a folder" && empty.caption == "See how much it grows each week" && empty.accessory == "Pin a Folder…")
        #expect(empty.accessibilityLabel == "Pin a folder. See how much it grows each week.")
        let measuring = make(room: .measuring(pinned)).room
        #expect(measuring.title == "Work" && measuring.caption == "Measuring…" && measuring.accessory == "—")
        #expect(measuring.accessibilityLabel == "Work, measuring. Open in Disk Map.")
        let unavailable = make(room: .unavailable(pinned)).room
        #expect(unavailable.title == "Room can't read this folder" && unavailable.caption == "Pin it again" && unavailable.accessory == nil)
        #expect(unavailable.accessibilityLabel == "Room can't read this folder. Pin it again.")
    }

    @Test func firstMeasurementTracksFromTodayAndFirstPartialResultNeverClaimsCompleteMeasurement() {
        let first = log([(date(2026, 11, 17, 9), 74_300_000_000, false)])
        let tracked = make(room: .measured(pinned, first)).room
        #expect(tracked.title == "Work" && tracked.accessory == "74.3 GB" && tracked.caption == "Tracking from today")
        let partial = log([(date(2026, 11, 17, 9), 74_300_000_000, true)])
        let incomplete = make(room: .measured(pinned, partial)).room
        #expect(incomplete.accessory == "≥ 74.3 GB" && incomplete.caption == "Some folders could not be read")
        #expect(incomplete.accessibilityLabel == "Work, at least 74.3 gigabytes, some folders could not be read. Open in Disk Map.")
    }

    @Test func partialBaselineSuppressesTheDeltaAndLossesUseSpokenMinus() {
        let partial = log([(date(2026, 11, 15, 20), 71_100_000_000, true),
                           (date(2026, 11, 17, 9), 74_300_000_000, false)])
        let incomplete = make(room: .measured(pinned, partial)).room
        #expect(incomplete.caption == "Some folders could not be read" && incomplete.accessory == "≥ 74.3 GB")
        let loss = log([(date(2026, 11, 15, 20), 75_400_000_000, false),
                        (date(2026, 11, 17, 9), 74_300_000_000, false)])
        let shrinking = make(room: .measured(pinned, loss)).room
        #expect(shrinking.caption == "−1.1 GB since Monday")
        #expect(shrinking.accessibilityLabel == "Work, 74.3 gigabytes, minus 1.1 gigabytes since Monday. Open in Disk Map.")
    }
}
