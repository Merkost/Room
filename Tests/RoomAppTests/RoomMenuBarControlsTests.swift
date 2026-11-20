import Foundation
import Testing
@testable import RoomApp

@Suite("Menu bar controls")
struct RoomMenuBarControlsTests {
    @Test(arguments: [
        (Int64.min, Int64(20_000_000_000)),
        (Int64(19_000_000_000), Int64(20_000_000_000)),
        (Int64(73_000_000_000), Int64(73_000_000_000)),
        (Int64.max, Int64(200_000_000_000))
    ])
    func goalClampUsesTheAllowedRange(_ fixture: (input: Int64, expected: Int64)) {
        #expect(RoomMenuBarSettings.clampGoalBytes(fixture.input) == fixture.expected)
    }

    @Test(arguments: [
        (Int64(50_000_000_000), 1, Int64(60_000_000_000)),
        (Int64(50_000_000_000), -1, Int64(40_000_000_000)),
        (Int64(20_000_000_000), -1, Int64(20_000_000_000)),
        (Int64(200_000_000_000), 1, Int64(200_000_000_000)),
        (Int64.min, Int.max, Int64(200_000_000_000)),
        (Int64.max, Int.min, Int64(20_000_000_000)),
        (Int64.min, 0, Int64(20_000_000_000))
    ])
    func goalStepsSafelyInTenGigabytes(_ fixture: (input: Int64, steps: Int, expected: Int64)) {
        #expect(RoomMenuBarSettings.goalStepBytes == 10_000_000_000)
        #expect(RoomMenuBarSettings.steppedGoalBytes(from: fixture.input, by: fixture.steps) == fixture.expected)
    }

    @Test func writingGoalClampsTheStoredValue() throws {
        try withDefaults { defaults in
            RoomMenuBarSettings.setGoalBytes(Int64.min, in: defaults)
            #expect(RoomMenuBarSettings.goalBytes(in: defaults) == RoomMenuBarSettings.minimumGoalBytes)
            #expect((defaults.object(forKey: RoomMenuBarSettings.goalBytesKey) as? NSNumber)?.int64Value == RoomMenuBarSettings.minimumGoalBytes)
            RoomMenuBarSettings.setGoalBytes(Int64.max, in: defaults)
            #expect(RoomMenuBarSettings.goalBytes(in: defaults) == RoomMenuBarSettings.maximumGoalBytes)
        }
    }

    @Test func neitherNoneControlCanHideTheOther() {
        #expect(!RoomMenuBarSettings.canSelectValue(.none, icon: .none))
        #expect(!RoomMenuBarSettings.canSelectIcon(.none, value: .none))
        #expect(RoomMenuBarSettings.canSelectValue(.none, icon: .mark))
        #expect(RoomMenuBarSettings.canSelectIcon(.none, value: .memory))
        #expect(RoomMenuBarSettings.canSelectValue(.disk, icon: .none))
        #expect(RoomMenuBarSettings.canSelectIcon(.symbol, value: .none))
    }

    @Test func valueWritesOnlyTheNewKeyAndLeavesLegacyPreferencesAlone() throws {
        try withDefaults { defaults in
            defaults.set("storage", forKey: RoomMenuBarSettings.legacyMetricKey)
            defaults.set(false, forKey: "RoomMonitorShowPressure")
            RoomMenuBarSettings.setValue(.both, in: defaults)
            #expect(defaults.string(forKey: RoomMenuBarSettings.valueKey) == "both")
            #expect(defaults.string(forKey: RoomMenuBarSettings.legacyMetricKey) == "storage")
            #expect(defaults.object(forKey: "RoomMonitorShowPressure") as? Bool == false)
            #expect(defaults.object(forKey: RoomMenuBarSettings.iconKey) == nil)
        }
    }

    @Test func rejectedNoneSelectionsLeaveTheirKeysUntouched() throws {
        try withDefaults { defaults in
            defaults.set("storage", forKey: RoomMenuBarSettings.legacyMetricKey)
            RoomMenuBarSettings.setIcon(.none, in: defaults)
            RoomMenuBarSettings.setValue(.none, in: defaults)
            #expect(defaults.object(forKey: RoomMenuBarSettings.valueKey) == nil)
            #expect(defaults.string(forKey: RoomMenuBarSettings.iconKey) == "none")
            RoomMenuBarSettings.setIcon(.mark, in: defaults)
            RoomMenuBarSettings.setValue(.none, in: defaults)
            RoomMenuBarSettings.setIcon(.none, in: defaults)
            #expect(defaults.string(forKey: RoomMenuBarSettings.valueKey) == "none")
            #expect(defaults.string(forKey: RoomMenuBarSettings.iconKey) == "mark")
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "RoomMenuBarControls-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
