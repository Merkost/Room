import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Menu bar preference read-through and announcements")
struct RoomMenuBarSettingsTests {
    private let gb: Int64 = 1_000_000_000

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "RoomMenuBarSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func report(total: Int64 = 32_000_000_000, used: Int64 = 24_800_000_000,
                        available: Int64 = 7_200_000_000, pressure: MemoryPressure = .elevated) -> MemoryReport {
        MemoryReport(id: UUID(), scannedAt: Date(), totalBytes: total, usedBytes: used,
            availableBytes: available, compressedBytes: 0, swapUsedBytes: 0,
            pressure: pressure, processes: [], recommendations: [], issues: [])
    }

    private func input(_ defaults: UserDefaults, report: MemoryReport? = nil,
                       capacity: Int64 = 994_000_000_000, available: Int64 = 312_000_000_000) -> RoomMenuBarInput {
        RoomMenuBarSettings.makeInput(defaults: defaults, memoryReport: report,
            diskCapacityBytes: capacity, diskAvailableBytes: available)
    }

    @Test func oldStorageKeysReadThroughWithoutWritingNewKeys() throws {
        try withDefaults { defaults in
            defaults.set("storage", forKey: "RoomMenuBarMetric")
            defaults.set(false, forKey: "RoomMonitorShowPressure")
            defaults.set(true, forKey: "RoomMonitorShowSwap")
            let result = input(defaults, report: report())
            #expect(result.value == .disk)
            #expect(result.icon == .mark && result.tintOnlyWhenNeeded)
            #expect(result.pressure == .elevated)
            #expect(result.diskFreeBytes == 312 * gb && result.goalBytes == 50 * gb)
            #expect(RoomMenuBarSettings.showSwap(in: defaults))
            #expect(defaults.object(forKey: "RoomMenuBarValue") == nil)
        }
    }

    @Test func oldMemoryKeyReadsThrough() throws {
        try withDefaults { defaults in
            defaults.set("memory", forKey: "RoomMenuBarMetric")
            #expect(input(defaults).value == .memory)
        }
    }

    @Test func newKeysBuildTheInput() throws {
        try withDefaults { defaults in
            defaults.set("both", forKey: "RoomMenuBarValue")
            defaults.set("symbol", forKey: "RoomMenuBarIcon")
            defaults.set(false, forKey: "RoomMenuBarTintOnlyWhenNeeded")
            defaults.set(Int64(80_000_000_000), forKey: "RoomGoalBytes")
            let result = input(defaults, report: report())
            #expect(result.value == .both && result.icon == .symbol && !result.tintOnlyWhenNeeded)
            #expect(result.goalBytes == 80 * gb)
            #expect(result.memoryUsedBytes == 24_800_000_000 && result.memoryTotalBytes == 32 * gb)
            #expect(result.pressure == .elevated && result.diskFreeBytes == 312 * gb)
        }
    }

    @Test func newValueTakesPrecedenceOverOldMetric() throws {
        try withDefaults { defaults in
            defaults.set("storage", forKey: "RoomMenuBarMetric")
            defaults.set("none", forKey: "RoomMenuBarValue")
            defaults.set("none", forKey: "RoomMenuBarIcon")
            let result = input(defaults)
            #expect(result.value == .none && result.icon == .none)
            #expect(RoomMenuBarPresentation.make(result, format: .fixtureGigabytes).icon == .mark)
        }
    }

    @Test func invalidNewValuesUseDefaultsWithoutReadingThrough() throws {
        try withDefaults { defaults in
            defaults.set("storage", forKey: "RoomMenuBarMetric")
            defaults.set("invalid", forKey: "RoomMenuBarValue")
            defaults.set("invalid", forKey: "RoomMenuBarIcon")
            let result = input(defaults)
            #expect(result.value == .memory && result.icon == .mark)
        }
    }

    @Test func absentKeysUseTheNewDefaults() throws {
        try withDefaults { defaults in
            let result = input(defaults, report: report())
            #expect(result.value == .memory && result.icon == .mark && result.tintOnlyWhenNeeded)
            #expect(result.goalBytes == 50_000_000_000)
            #expect(!RoomMenuBarSettings.showSwap(in: defaults))
        }
    }

    @Test(arguments: [
        (Int64.min, Int64(20_000_000_000)),
        (Int64(0), Int64(20_000_000_000)),
        (Int64(20_000_000_000), Int64(20_000_000_000)),
        (Int64(73_000_000_000), Int64(73_000_000_000)),
        (Int64(200_000_000_000), Int64(200_000_000_000)),
        (Int64.max, Int64(200_000_000_000))
    ])
    func goalClampsInDecimalBytes(_ values: (stored: Int64, expected: Int64)) throws {
        try withDefaults { defaults in
            defaults.set(values.stored, forKey: "RoomGoalBytes")
            #expect(input(defaults).goalBytes == values.expected)
        }
    }

    @Test(arguments: [false, true])
    func storedSwapPreferenceIsKept(_ stored: Bool) throws {
        try withDefaults { defaults in
            defaults.set(stored, forKey: "RoomMonitorShowSwap")
            #expect(RoomMenuBarSettings.showSwap(in: defaults) == stored)
        }
    }

    @Test func unavailableMeasurementsStayUnavailable() throws {
        try withDefaults { defaults in
            let missing = input(defaults, capacity: 0, available: 0)
            #expect(missing.memoryUsedBytes == nil && missing.memoryTotalBytes == nil && missing.diskFreeBytes == nil)
            let failedCounters = input(defaults, report: report(used: 0, available: 0))
            #expect(failedCounters.memoryUsedBytes == nil && failedCounters.pressure == .unknown)
            let noTotal = input(defaults, report: report(total: 0))
            #expect(noTotal.memoryUsedBytes == nil && noTotal.memoryTotalBytes == nil)
        }
    }

    @Test func measuredValuesClampToTheirCapacities() throws {
        try withDefaults { defaults in
            #expect(input(defaults, report: report(used: 40 * gb)).memoryUsedBytes == 32 * gb)
            #expect(input(defaults, report: report(used: -1)).memoryUsedBytes == 0)
            #expect(input(defaults, capacity: 100, available: 200).diskFreeBytes == 100)
            #expect(input(defaults, capacity: 100, available: -1).diskFreeBytes == 0)
        }
    }

    @Test func thirtyValueChangesWithTwoToneChangesAnnounceTwice() {
        var announcer = RoomMenuBarAnnouncer()
        var announced = 0
        let sequence: [(Double, RoomMenuBarPressure)] =
            (0..<12).map { (16.0 + Double($0) * 0.1, .normal) }
            + (0..<10).map { (24.0 + Double($0) * 0.1, .elevated) }
            + (0..<8).map { (17.0 + Double($0) * 0.1, .normal) }
        for (used, pressure) in sequence {
            let value = RoomMenuBarInput(value: .memory, memoryUsedBytes: Int64(used * 1e9),
                memoryTotalBytes: 32 * gb, pressure: pressure)
            let output = RoomMenuBarPresentation.make(value, format: .fixtureGigabytes)
            if announcer.shouldAnnounce(output.announcementKey) { announced += 1 }
        }
        #expect(sequence.count == 30 && announced == 2)
    }

    @Test func firstValueIsNotAnnounced() {
        var announcer = RoomMenuBarAnnouncer()
        let announced = announcer.shouldAnnounce("m0d-")
        #expect(!announced)
    }
}
