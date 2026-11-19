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
        check("DMR-C50_GivenNameUsed", RoomGreetingName.resolve(fullName: "Konstantin Merenkov", loginName: "kostakttipay", givenName: { _ in "Konstantin" }) == "Konstantin")
        check("DMR-C51_FallbackFirstWord", RoomGreetingName.resolve(fullName: "Kostya M", loginName: "k", givenName: { _ in nil }) == "Kostya")
        check("DMR-C52_LoginNameIsNoName", RoomGreetingName.resolve(fullName: "kostakttipay", loginName: "kostakttipay", givenName: { _ in nil }) == nil)
        check("DMR-C53_EmptyNameNoName", RoomGreetingName.resolve(fullName: "  ", loginName: "x", givenName: { _ in "x" }) == nil)
        check("DMR-C54_GreetingBoundaries", RoomGreetingName.line(hour: 4, enabled: true, name: "K", hidden: false) == "Good evening, K"
              && RoomGreetingName.line(hour: 5, enabled: true, name: "K", hidden: false) == "Good morning, K"
              && RoomGreetingName.line(hour: 12, enabled: true, name: "K", hidden: false) == "Good afternoon, K"
              && RoomGreetingName.line(hour: 18, enabled: true, name: "K", hidden: false) == "Good evening, K")
        check("DMR-C55_HideDropsName", RoomGreetingName.line(hour: 9, enabled: true, name: "K", hidden: true) == "Good morning.")
        check("DMR-C56_SwitchOffRemovesLine", RoomGreetingName.line(hour: 9, enabled: false, name: "K", hidden: false) == nil)
        check("DMR-C57_NextBoundaryNoPolling", RoomGreetingName.nextBoundary(after: date(2026, 11, 19, 11, 59), calendar: cal) == date(2026, 11, 19, 12)
              && RoomGreetingName.nextBoundary(after: date(2026, 11, 19, 18), calendar: cal) == date(2026, 11, 20, 5))
        let prefs = RoomOverviewPreferences.read(["RoomGreetingEnabled": "yes"])
        check("DMR-C58_BadPreferenceReadsDefault", prefs.greetingEnabled && prefs.roomsChapterShown)
        check("DMR-C59_ResetNeverForgetsRecords", !RoomOverviewPreferences.resetKeys.contains { $0.contains("Room") && $0.contains("Bytes") } && !RoomOverviewPreferences.resetKeys.contains("RoomGoalBytes"))
        check("DMR-C60_NoRoomsNoPickerNoChapter", !RoomOverviewPreferences().showsRoomsChapter(roomCount: 0, canPin: false)
              && RoomOverviewPreferences().showsRoomsChapter(roomCount: 0, canPin: true))

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

    @Test @MainActor func greetingReadsNameOnlyOnActivationAndChangesLive() {
        var reads = 0
        let model = RoomOverviewModel(fullName: { reads += 1; return "Casey Example" },
                                      loginName: { "caseyexample" }, givenName: { _ in "Casey" })
        #expect(reads == 0)
        model.updateGreeting(enabled: true, hidden: false, refreshName: true)
        #expect(model.greeting?.contains("Casey") == true)
        #expect(reads == 1)
        model.updateGreeting(enabled: true, hidden: true)
        #expect(model.greeting?.contains("Casey") == false)
        model.updateGreeting(enabled: false, hidden: false)
        #expect(model.greeting == nil && model.nextGreetingUpdateAt == nil)
        #expect(reads == 1)
    }

    @Test func customiseOnlyWithOverview() {
        let overview = RoomMenuModel.make(.init(destination: .overview, window: .main))
        let memory = RoomMenuModel.make(.init(destination: .memory, window: .main))
        #expect(overview.first { $0.id == .customiseOverview }?.shortcut == .init("c", [.option, .command]))
        #expect(!memory.contains { $0.id == .customiseOverview })
        #expect(!RoomMenuModel.make(.init(destination: .overview, window: .modal)).contains { $0.id == .customiseOverview })
    }
}
