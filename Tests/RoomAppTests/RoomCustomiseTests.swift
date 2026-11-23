import Foundation
import Testing
@testable import RoomApp

@Suite("Overview personal touches")
struct RoomCustomiseTests {
    @Test func greetingAndPreferencesReference() {
        func check(_ id: String, _ passed: Bool) { #expect(passed, Comment(rawValue: id)) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
        }
        check("DMR-C54_GreetingBoundaries", RoomGreetingName.line(hour: 4) == "Good evening."
              && RoomGreetingName.line(hour: 5) == "Good morning."
              && RoomGreetingName.line(hour: 12) == "Good afternoon."
              && RoomGreetingName.line(hour: 18) == "Good evening.")
        check("DMR-C57_NextBoundaryNoPolling", RoomGreetingName.nextBoundary(after: date(2026, 11, 19, 11, 59), calendar: cal) == date(2026, 11, 19, 12)
              && RoomGreetingName.nextBoundary(after: date(2026, 11, 19, 18), calendar: cal) == date(2026, 11, 20, 5))
        let prefs = RoomOverviewPreferences.read(["RoomChapterRoomsShown": "yes"])
        check("DMR-C58_BadPreferenceReadsDefault", prefs.roomsChapterShown)
        check("DMR-C59_ResetNeverForgetsRecords", !RoomOverviewPreferences.resetKeys.contains { $0.contains("Room") && $0.contains("Bytes") } && !RoomOverviewPreferences.resetKeys.contains("RoomGoalBytes"))
        check("DMR-C60_EmptyChapterUsesOverviewContext", !RoomOverviewPreferences().showsRoomsChapter(roomCount: 0, allowsEmptyChapter: false)
              && RoomOverviewPreferences().showsRoomsChapter(roomCount: 0, allowsEmptyChapter: true)
              && RoomOverviewPreferences().showsRoomsChapter(roomCount: 1, allowsEmptyChapter: false)
              && !RoomOverviewPreferences(roomsChapterShown: false).showsRoomsChapter(roomCount: 1, allowsEmptyChapter: true))

    }

    @Test func rulerReference() {
        func check(_ id: String, _ passed: Bool) { #expect(passed, Comment(rawValue: id)) }
        let gb: Int64 = 1_000_000_000
        let validStored = Set(stride(from: 20, through: 200, by: 10).map { Int64($0) * gb })

        // A fling at 1 200 pt/s (1.2 pt/ms) from 50 GB on a 994 GB Mac rests on a 10 GB detent (PE-A2).
        let rest = RoomGoalRuler.restingGB(currentGB: 50, releaseVelocityPtPerMS: 1.2, capacityGB: 994)
        check("DMR-R01_FlingRestsOnDetent", rest.truncatingRemainder(dividingBy: 10) == 0 && rest >= 20 && rest <= 200)
        check("DMR-R02_FlingEqualsSnapOfProjection",
              rest == RoomPure.nearestStep(50 - RoomPure.project(velocityPtPerMS: 1.2) / 2.4, step: 10, min: 20, max: 200))
        check("DMR-R03_StoredBytesAlwaysASettingsValue",
              stride(from: -40.0, through: 260.0, by: 3.7).allSatisfy { validStored.contains(RoomGoalRulerBridge.storedBytes(restingGB: $0, capacityGB: 994)) })
        check("DMR-R04_SmallDiskUpperBound", RoomGoalRuler.upperGB(capacityGB: 128) == 118
              && RoomGoalRulerBridge.step(100 * gb, key: .end, capacityGB: 128) == 110 * gb
              && RoomGoalRulerBridge.storedBytes(restingGB: RoomGoalRuler.restingGB(currentGB: 110, releaseVelocityPtPerMS: -3, capacityGB: 128), capacityGB: 128) == 110 * gb)
        check("DMR-R05_ArrowsAndPages", RoomGoalRulerBridge.step(50 * gb, key: .right, capacityGB: 994) == 60 * gb
              && RoomGoalRulerBridge.step(50 * gb, key: .pageDown, capacityGB: 994) == 20 * gb
              && RoomGoalRulerBridge.step(190 * gb, key: .pageUp, capacityGB: 994) == 200 * gb)
        check("DMR-R06_HomeIsTwenty", RoomGoalRulerBridge.step(120 * gb, key: .home, capacityGB: 994) == 20 * gb)
        check("DMR-R07_OneHapticPerDetent", RoomGoalRulerBridge.detentsCrossed(from: 50, to: 81) == 3
              && RoomGoalRulerBridge.detentsCrossed(from: 50, to: 54) == 0)
        check("DMR-R08_RubberBandBounded", RoomGoalRuler.dragValue(startGB: 20, dragPoints: 2_400, capacityGB: 994) > 20 - 40 - 1e-9
              && RoomGoalRuler.dragValue(startGB: 20, dragPoints: 2_400, capacityGB: 994) < 20)
        check("DMR-R10_RubberValueIsNeverStored", RoomGoalRulerBridge.storedBytes(restingGB: RoomGoalRuler.dragValue(startGB: 20, dragPoints: 2_400, capacityGB: 994), capacityGB: 994) == 20 * gb)
        check("DMR-R09_CoastCapped", RoomPure.coastMS(distanceGB: 1_000) == 620 && RoomPure.coastMS(distanceGB: 0) == 260)

    }

    @Test @MainActor func greetingIsGenericAndSchedulesNextBoundary() {
        let model = RoomOverviewModel()
        model.updateGreeting()
        #expect(model.greeting?.hasPrefix("Good ") == true && model.greeting?.contains(",") == false)
        #expect(model.nextGreetingUpdateAt != nil)
    }

    @Test func customiseOnlyWithOverview() {
        let overview = RoomMenuModel.make(.init(destination: .overview, window: .main))
        let memory = RoomMenuModel.make(.init(destination: .memory, window: .main))
        #expect(overview.first { $0.id == .customiseOverview }?.shortcut == .init("c", [.option, .command]))
        #expect(!memory.contains { $0.id == .customiseOverview })
        #expect(!RoomMenuModel.make(.init(destination: .overview, window: .modal)).contains { $0.id == .customiseOverview })
    }
}
