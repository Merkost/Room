#if !ROOM_APP_STORE
import Foundation
import Testing
@testable import RoomApp

struct RoomWeeklyCheckTests {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_600_000_000)

    private func record(_ days: Int, bytes: Int64, partial: Bool = false, scope: String = "quick") -> RoomWeeklyCheckRecord {
        RoomWeeklyCheckRecord(at: base.addingTimeInterval(day * Double(days)), eligibleBytes: bytes, partial: partial, scope: scope)
    }

    @MainActor @Test func hideOmitsTheSizeFromTheNotificationTitle() {
        let shown = RoomWeeklyCheckScheduler.title(growth: 7_000_000_000, hideSizes: false)
        let hidden = RoomWeeklyCheckScheduler.title(growth: 7_000_000_000, hideSizes: true)
        #expect(shown.contains(RoomFormat.gb(7_000_000_000)))
        #expect(!hidden.contains(where: \.isNumber) && !hidden.contains("GB"))
    }

    @Test func onlyMatchingCompleteWeeklyMeasurementsCanNotify() {
        let previous = record(0, bytes: 10)
        #expect(RoomWeeklyCheck.growthToReport(previous: nil, current: record(7, bytes: 15), thresholdBytes: 5) == nil)
        #expect(RoomWeeklyCheck.growthToReport(previous: previous, current: record(7, bytes: 15), thresholdBytes: 5) == 5)
        #expect(RoomWeeklyCheck.growthToReport(previous: previous, current: record(14, bytes: 15), thresholdBytes: 5) == 5)
        #expect(RoomWeeklyCheck.growthToReport(previous: previous, current: record(15, bytes: 15), thresholdBytes: 5) == nil)
        #expect(RoomWeeklyCheck.growthToReport(previous: previous, current: record(5, bytes: 15), thresholdBytes: 5) == nil)
        #expect(RoomWeeklyCheck.growthToReport(previous: previous, current: record(7, bytes: 14), thresholdBytes: 5) == nil)
        #expect(RoomWeeklyCheck.growthToReport(previous: previous, current: record(7, bytes: 50, partial: true), thresholdBytes: 5) == nil)
        #expect(RoomWeeklyCheck.growthToReport(previous: previous, current: record(7, bytes: 50, scope: "full"), thresholdBytes: 5) == nil)
        #expect(RoomWeeklyCheck.nextRecord(previous: previous, current: record(7, bytes: 50, partial: true)) == previous)
    }

    @MainActor @Test func deniedPermissionTurnsSwitchOff() async throws {
        let suite = "RoomWeeklyCheck-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scheduler = RoomWeeklyCheckScheduler(defaults: defaults,
            writer: RoomStateWriter(store: RoomStateStore(directory: directory)), requestPermission: { false })
        #expect(!scheduler.enabled)
        scheduler.setEnabled(true)
        #expect(scheduler.permissionPending)
        await scheduler.waitForAuthorization()
        #expect(scheduler.permissionDenied && !scheduler.enabled && !scheduler.permissionPending)
        #expect(!defaults.bool(forKey: RoomWeeklyCheckScheduler.enabledKey))
    }
}
#endif
