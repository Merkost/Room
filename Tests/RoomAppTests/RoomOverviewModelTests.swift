import CoreGraphics
import Foundation
import Testing
@testable import RoomApp

@Suite("Overview snapshot")
struct RoomOverviewModelTests {
    private let gb: Int64 = 1_000_000_000
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func input(free: Int64? = 312_000_000_000, capacity: Int64? = 994_000_000_000,
                       goal: Int64? = 50_000_000_000, caches: RoomCachesCheck? = nil,
                       invalidatedAt: Date? = nil, hidden: Bool = false) -> RoomOverviewInput {
        .init(capacityBytes: capacity, freeBytes: free, goalBytes: goal, caches: caches,
              cachesInvalidatedAt: invalidatedAt, now: now, hidden: hidden)
    }

    private func snapshot(_ input: RoomOverviewInput) -> RoomOverviewSnapshot {
        RoomOverviewSnapshot.make(input, format: RoomMenuBarFormat.fixtureGigabytes.memory)
    }

    private func caches(_ bytes: Int64 = 8_400_000_000, partial: Bool = false, age: TimeInterval = 60) -> RoomCachesCheck {
        .init(at: now.addingTimeInterval(-age), bytes: bytes, partial: partial)
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

    @Test func firstRunUsesBoardIntroWithMeasuredPlan() {
        var new = input(free: 17 * gb, hidden: true)
        new.mapActionAvailable = true
        let intro = snapshot(new)
        #expect(intro.state == .firstRun)
        #expect(intro.answer == "Room starts by looking.")
        #expect(intro.accessibilityAnswer == "Room starts by looking. Nothing moves until you say so.")
        #expect(intro.action == .mapMac)
        #expect(intro.plan?.freeBytes == 17 * gb)
        #expect(intro.plan?.goalBytes == nil)

        new.caches = caches(age: RoomOverviewSnapshot.cacheFreshness)
        new.hidden = false
        #expect(snapshot(new).state == .belowGoal)
    }

    @Test func capacitySplitKeepsGoalOnTheUsedSpaceScale() throws {
        let plan = try #require(snapshot(input(free: 20 * gb, capacity: 100 * gb)).plan)
        let balance = RoomOverviewCapacityBalance(plan: plan, goal: 25 * gb)
        #expect(balance.usedBytes == 80 * gb)
        #expect(balance.usedFraction == 0.8)
        #expect(balance.goalPosition == 0.75)
        #expect(balance.goalDifference == -5 * gb)
        #expect(RoomOverviewCapacityBalance(plan: plan, goal: 101 * gb).goalPosition == nil)
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

    @Test("OVC-19_PositiveCachesMakeRoom") func positiveCachesMakeRoom() {
        #expect(snapshot(input(caches: caches())).action == .makeRoom(bytes: 8_400_000_000, partial: false))
    }

    @Test("OVC-20_PartialPositiveHasLowerBound") func partialPositiveHasLowerBound() {
        #expect(snapshot(input(caches: caches(partial: true))).actionTitle == "Make room · ≥ 8.4 GB")
    }

    @Test("OVC-21_PartialZeroIsNotNone") func partialZeroIsNotNone() {
        #expect(snapshot(input(caches: caches(0, partial: true))).action == .checkCaches)
    }

    @Test("OVC-22_CompleteBelow100MBLinkOnly") func completeBelow100MBLinkOnly() {
        #expect(snapshot(input(caches: caches(99_999_999))).action == .usingSpaceOnly)
    }

    @Test("OVC-23_Exactly100MBIsActionable") func exactly100MBIsActionable() {
        #expect(snapshot(input(caches: caches(100_000_000))).action == .makeRoom(bytes: 100_000_000, partial: false))
    }

    @Test("OVC-24_Exactly24HoursIsStale") func exactly24HoursIsStale() {
        #expect(snapshot(input(caches: caches(age: 86_400))).action == .checkCaches)
    }

    @Test("OVC-25_Before24HoursIsFresh") func before24HoursIsFresh() {
        #expect(snapshot(input(caches: caches(age: 86_399))).action != .checkCaches)
    }

    @Test("OVC-26_FutureTimestampRejected") func futureTimestampRejected() {
        #expect(snapshot(input(caches: caches(age: -1))).cachesCheckedAt == nil)
    }

    @Test("OVC-27_NegativeCachesRejected") func negativeCachesRejected() {
        #expect(snapshot(input(caches: caches(-1))).action == .checkCaches)
    }

    @Test("OVC-28_MutationAfterCheckInvalidates") func mutationAfterCheckInvalidates() {
        #expect(snapshot(input(caches: caches(), invalidatedAt: now)).action == .checkCaches)
    }

    @Test("OVC-29_OlderMutationKeepsCheck") func olderMutationKeepsCheck() {
        #expect(snapshot(input(caches: caches(), invalidatedAt: now.addingTimeInterval(-120))).action != .checkCaches)
    }

    @Test("OVC-30_DateRetainedForQuietLine") func dateRetainedForQuietLine() {
        #expect(snapshot(input(caches: caches(age: 90_000))).cachesCheckedAt == now.addingTimeInterval(-90_000))
    }

    @Test("OVC-31_HideMasksAllDigits") func hideMasksAllDigits() {
        let hidden = snapshot(input(caches: caches(partial: true), hidden: true))
        #expect(!hidden.answer.contains(where: \.isNumber) && !hidden.sentence.contains(where: \.isNumber))
    }

    @Test("OVC-32_HideActionDropsSize") func hideActionDropsSize() {
        let hidden = snapshot(input(caches: caches(partial: true), hidden: true))
        #expect(hidden.actionTitle == "Make room")
    }

    @Test("OVC-33_HideAXHasNoRawSizes") func hideAXHasNoRawSizes() {
        let hidden = snapshot(input(caches: caches(partial: true), hidden: true))
        #expect(hidden.accessibilityAnswer == "Free space and goal hidden." && hidden.accessibilityAction == "Make room. Opens Caches. Sizes hidden.")
    }

    @Test("OVC-34_HidePreservesGeometry") func hidePreservesGeometry() {
        let normal = snapshot(input())
        let hidden = snapshot(input(caches: caches(partial: true), hidden: true))
        #expect(hidden.plan == normal.plan)
    }

    @Test("OVC-36_BoardUnmappedCounts") func boardUnmappedCounts() {
        let normal = snapshot(input())
        #expect(normal.plan?.freeDots == 78 && normal.plan?.notMappedDots == 0 && normal.plan?.gbPerDot == 4)
    }

    @Test("OVC-37_NoInventedKindDots") func noInventedKindDots() throws {
        let blankPlan = try #require(snapshot(input()).plan).layout(size: CGSize(width: 560, height: 288))
        #expect(blankPlan.dots.count == 78 && blankPlan.dots.allSatisfy { $0.room == .free })
    }

    @Test("OVC-38_ExistingBoardFixture250") func existingBoardFixture250() {
        let full = RoomDotPlan.make(capacityGB: 994, freeGB: 312,
            kinds: [("developer", 239), ("system", 174), ("apps", 102), ("media", 94),
                    ("documents", 41), ("archives", 20), ("hidden", 12)], size: CGSize(width: 560, height: 288))
        #expect(full.dots.count == 250 && full.dots.filter { $0.room == .free }.count == 78)
    }

    @Test("OVC-39_ExistingFixtureErrorSixGB") func existingFixtureErrorSixGB() {
        let full = RoomDotPlan.make(capacityGB: 994, freeGB: 312,
            kinds: [("developer", 239), ("system", 174), ("apps", 102), ("media", 94),
                    ("documents", 41), ("archives", 20), ("hidden", 12)], size: CGSize(width: 560, height: 288))
        #expect(abs(full.drawnErrorGB - 6) < 0.0001)
    }

    @Test("OVC-40_UnderOneDotAccessible") func underOneDotAccessible() throws {
        let tiny = snapshot(input(free: gb))
        let tinyLayout = try #require(tiny.plan).layout(size: CGSize(width: 560, height: 288))
        #expect(tiny.plan?.freeDots == 0 && tinyLayout.underOneDot.contains(.free))
    }

    @Test("OVC-41_AllFreeHasNoRemainder") func allFreeHasNoRemainder() {
        #expect(snapshot(input(free: 994 * gb)).plan?.notMappedBytes == 0)
    }

    @Test("OVC-42_PartialNoGoalSpeaksAtLeast") func partialNoGoalSpeaksAtLeast() {
        #expect(snapshot(input(goal: nil, caches: caches(partial: true))).accessibilityAnswer.contains("at least 8.4 GB"))
    }

    @Test("OVC-43_UnknownNoGoalOmitsOutline") func unknownNoGoalOmitsOutline() {
        let disabled = snapshot(input(goal: nil))
        #expect(disabled.plan?.goalBytes == nil)
    }

    @Test("OVC-44_BelowGoalHidesGoalOutline") func belowGoalHidesGoalOutline() {
        let below = snapshot(input(free: 41 * gb, caches: caches()))
        #expect(below.plan?.goalBytes == nil)
    }

    @Test("OVC-45_AboveGoalKeepsGoalOutline") func aboveGoalKeepsGoalOutline() {
        let normal = snapshot(input())
        #expect(normal.plan?.goalBytes == 50 * gb)
    }

    @Test("OVC-46_EqualTimestampInvalidates") func equalTimestampInvalidates() {
        #expect(snapshot(input(caches: caches(), invalidatedAt: now.addingTimeInterval(-60))).action == .checkCaches)
    }

    @Test("OVC-47_PartialSmallNoReassurance") func partialSmallNoReassurance() {
        #expect(snapshot(input(goal: nil, caches: caches(500_000_000, partial: true))).sentence == "Nothing moves until you say so.")
    }

    @Test("OVC-48_StaleNoGoalNoReassurance") func staleNoGoalNoReassurance() {
        #expect(snapshot(input(goal: nil, caches: caches(age: 86_400))).sentence == "Nothing moves until you say so.")
    }

    @Test("OVC-49_InvalidatedNoGoalNoReassurance") func invalidatedNoGoalNoReassurance() {
        #expect(snapshot(input(goal: nil, caches: caches(), invalidatedAt: now)).sentence == "Nothing moves until you say so.")
    }

    @Test("OVC-51_ZeroFreeLayoutHonest") func zeroFreeLayoutHonest() throws {
        let zeroFree = try #require(snapshot(input(free: 0)).plan).layout(size: CGSize(width: 560, height: 288))
        #expect(zeroFree.dots.isEmpty && zeroFree.rooms.map(\.id) == [.notMapped])
    }

    @Test("OVC-52_LadderThroughEightTB") func ladderThroughEightTB() {
        #expect([128.0, 256, 512, 994, 2_000, 8_000].map(RoomPure.gbPerDot(capacityGB:)) == [1, 1, 2, 4, 10, 50])
    }

    @Test("OVC-53_HiddenNoGoalNoLeak") func hiddenNoGoalNoLeak() {
        let hiddenNoGoal = snapshot(input(goal: nil, caches: caches(partial: true), hidden: true))
        #expect(hiddenNoGoal.accessibilityAnswer == "Free space and goal hidden." && !hiddenNoGoal.sentence.contains(where: \.isNumber))
    }

    @Test("OVC-54_CheckAtExactlyNowIsUsable") func checkAtExactlyNowIsUsable() {
        let finished = snapshot(input(caches: caches(age: 0)))
        #expect(finished.action == .makeRoom(bytes: 8_400_000_000, partial: false))
        #expect(finished.cachesCheckedAt == now)
    }
}
