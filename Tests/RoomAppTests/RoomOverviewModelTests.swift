import Foundation
import Testing
@testable import RoomApp

@Suite("Overview snapshot")
struct RoomOverviewModelTests {
    private let gb: Int64 = 1_000_000_000
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func input(free: Int64? = 312_000_000_000, capacity: Int64? = 994_000_000_000,
                       goal: Int64? = 50_000_000_000, caches: RoomCachesCheck? = nil) -> RoomOverviewInput {
        .init(capacityBytes: capacity, freeBytes: free, goalBytes: goal, caches: caches,
              cachesInvalidatedAt: nil, now: now, hidden: false)
    }

    private func snapshot(_ input: RoomOverviewInput) -> RoomOverviewSnapshot {
        RoomOverviewSnapshot.make(input, format: RoomMenuBarFormat.fixtureGigabytes.memory)
    }

    private func caches(_ bytes: Int64 = 8_400_000_000) -> RoomCachesCheck {
        .init(at: now.addingTimeInterval(-60), bytes: bytes, partial: false)
    }

    @Test("OVC-01_AnswerUsesMeasuredFree") func answerUsesMeasuredFree() {
        let normal = snapshot(input())
        #expect(normal.answer == "You have 312 GB of room.")
    }

    @Test("OVC-02_AboveGoal") func aboveGoal() {
        let normal = snapshot(input())
        #expect(normal.sentence == "262 GB above your 50 GB goal. Nothing needs your attention.")
    }

    @Test("OVC-03_NoHomeKindsIsNotMapped") func noHomeKindsIsNotMapped() {
        let normal = snapshot(input())
        #expect(normal.state == .notMapped)
    }

    @Test("OVC-04_UnmappedBytes") func unmappedBytes() {
        let normal = snapshot(input())
        #expect(normal.plan?.notMappedBytes == 682 * gb)
    }

    @Test("OVC-05_MissingCachesOffersCheck") func missingCachesOffersCheck() {
        let normal = snapshot(input())
        #expect(normal.action == .checkCaches)
    }

    @Test("OVC-06_BelowGoalOutranksUnmapped") func belowGoalOutranksUnmapped() {
        let below = snapshot(input(free: 41 * gb, caches: caches()))
        #expect(below.state == .belowGoal)
    }

    @Test("OVC-07_NoImmediateSpacePrediction") func noImmediateSpacePrediction() {
        let below = snapshot(input(free: 41 * gb, caches: caches()))
        #expect(below.sentence == "9 GB under your 50 GB goal.")
    }

    @Test("OVC-08_AtGoal") func atGoal() {
        #expect(snapshot(input(free: 50 * gb)).sentence == "At your 50 GB goal. Nothing needs your attention.")
    }

    @Test("OVC-09_MissingIsUnavailable") func missingIsUnavailable() {
        let missing = snapshot(input(free: nil))
        #expect(missing.state == .capacityUnreadable && missing.plan == nil)
    }

    @Test("OVC-10_UnavailableRetriesOnly") func unavailableRetriesOnly() {
        let missing = snapshot(input(free: nil))
        #expect(missing.action == .retryCapacity
            && missing.cachesCheckedAt == nil)
    }

    @Test("OVC-11_ZeroCapacityInvalid") func zeroCapacityInvalid() {
        #expect(snapshot(input(free: 0, capacity: 0)).plan == nil)
    }

    @Test("OVC-12_FreeAboveCapacityInvalid") func freeAboveCapacityInvalid() {
        #expect(snapshot(input(free: 995 * gb)).plan == nil)
    }

    @Test("OVC-13_NegativeFreeInvalid") func negativeFreeInvalid() {
        #expect(snapshot(input(free: -1)).plan == nil)
    }

    @Test("OVC-14_MissingCapacityInvalid") func missingCapacityInvalid() {
        #expect(snapshot(input(capacity: nil)).plan == nil)
    }

    @Test("OVC-15_MeasuredZeroIsReal") func measuredZeroIsReal() {
        #expect(snapshot(input(free: 0)).answer == "You have 0 GB of room.")
    }

    @Test("OVC-16_NoGoalUnknownNotReassured") func noGoalUnknownNotReassured() {
        let disabled = snapshot(input(goal: nil))
        #expect(disabled.sentence == "Nothing moves until you say so.")
    }

    @Test("OVC-17_NoGoalKnownSmall") func noGoalKnownSmall() {
        #expect(snapshot(input(goal: nil, caches: caches(500_000_000))).sentence == "Nothing needs your attention.")
    }

    @Test("OVC-18_NoGoalOneGBThreshold") func noGoalOneGBThreshold() {
        #expect(snapshot(input(goal: nil, caches: caches(gb))).sentence == "1 GB of caches can go.")
    }

    @Test("OVC-35_GreetingBoundaries") func greetingBoundaries() {
        #expect([5, 12, 18, 0].map(RoomOverviewCopy.greeting(hour:)) == ["Good morning.", "Good afternoon.", "Good evening.", "Good evening."])
    }

    @Test("OVC-50_NonpositiveGoalDisabled") func nonpositiveGoalDisabled() {
        #expect([Int64(0), -1].allSatisfy { snapshot(input(goal: $0)).plan?.goalBytes == nil })
    }
}
