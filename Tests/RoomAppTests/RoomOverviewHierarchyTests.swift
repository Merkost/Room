import Foundation
import RoomCore
import Testing
@testable import RoomApp

/// REVIEW 2026-11-23 §3 Overview and §2.9: hierarchy, honest wording, labelled goal, the caption swap.
@MainActor
struct RoomOverviewHierarchyTests {
    @Test func historyLineNeverSaysFreed() {
        let more = RoomOverviewHistoryCopy.volumeLine(bytes: -39_000_000_000, since: "Monday", amount: "39 GB")
        #expect(more == "39 GB more free than Monday.")
        for bytes: Int64 in [-39_000_000_000, 0, 12_000_000_000] {
            let line = RoomOverviewHistoryCopy.volumeLine(bytes: bytes, since: "Monday", amount: "39 GB")
            #expect(!line.localizedCaseInsensitiveContains("freed"), "\(line)")
            #expect(!line.hasPrefix("Made"), "only the ledger-backed receipt may say Made")
        }
    }

    @Test func goalIsLabelledAtTheMarker() {
        #expect(RoomOverviewGoalCopy.marker(50_000_000_000) == "Goal \(RoomFormat.gb(50_000_000_000))")
        #expect(RoomOverviewGoalCopy.spoken(50_000_000_000).hasPrefix("Goal: keep"))
        let plan = RoomOverviewPlanInput(capacityBytes: 494_000_000_000, freeBytes: 64_000_000_000,
                                         goalBytes: 50_000_000_000)
        let balance = RoomOverviewCapacityBalance(plan: plan, goal: 50_000_000_000)
        let position = try! #require(balance.goalPosition)
        #expect(abs(position - (1 - 50.0 / 494.0)) < 0.0001, "the label sits where the marker is")
    }

    @Test func hiddenKindIsNamedHiddenFiles() {
        #expect(StorageKind.hidden.title == "Hidden files")
        #expect(StorageKind.hidden.explanation?.contains(".gradle") == true)
        #expect(StorageKind.developer.explanation == nil)
        #expect(RoomOverviewStorageMap.explanation(.kind("hidden")) == StorageKind.hidden.explanation)
        #expect(RoomOverviewStorageMap.explanation(.free) == nil)
    }

    @Test func arrivalPlaysOncePerLaunchAndNeverFromKeyboard() {
        #expect(RoomOverviewArrival.plays(origin: .programmatic, needsWelcome: false, hasLeftOverview: false))
        #expect(RoomOverviewArrival.plays(origin: .pointer, needsWelcome: false, hasLeftOverview: false))
        #expect(!RoomOverviewArrival.plays(origin: .keyboard, needsWelcome: false, hasLeftOverview: false))
        #expect(!RoomOverviewArrival.plays(origin: .pointer, needsWelcome: false, hasLeftOverview: true), "never on revisit")
        #expect(!RoomOverviewArrival.plays(origin: .programmatic, needsWelcome: true, hasLeftOverview: false))
    }

    @Test func captionsNeverOverlap() {
        // The old caption is gone before the new one starts to appear.
        #expect(RoomPanelChangeTiming.insertionDelay >= RoomPanelChangeTiming.removal)
        #expect(RoomPanelChangeTiming.removal == RoomDS.Motion.Duration.quick.seconds)
        #expect(RoomPanelChangeTiming.insertion == RoomDS.Motion.Duration.standard.seconds)
    }
}
