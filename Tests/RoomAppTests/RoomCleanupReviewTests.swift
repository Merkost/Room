import Foundation
import Testing
@testable import RoomApp

struct RoomCleanupReviewTests {
    @Test func commitLabelEqualsSelectedSumAtEveryToggle() {
        let a = RoomCleanupReview.Row(id: "a", name: "A", bytes: 7, consequence: "Rebuilt", entryIDs: [UUID()], parentFolders: ["/a"])
        let b = RoomCleanupReview.Row(id: "b", name: "B", bytes: 14, consequence: "Rebuilt", entryIDs: [UUID()], parentFolders: ["/b"])
        var review = RoomCleanupReview(rows: [a, b], selected: ["a", "b"], store: false)
        #expect(review.commit == .move(21))
        review.toggle("a")
        #expect(review.commit == .move(14) && review.selectedEntryIDs == b.entryIDs)
        review.toggle("b")
        #expect(review.commit == .selectAtLeastOne)
        #expect(!review.canCommit)
    }

    @Test func narrowingKeepsSharedGrants() {
        let a = RoomCleanupReview.Row(id: "a", name: "A", bytes: 7, consequence: "", entryIDs: [], parentFolders: ["/a", "/shared"])
        let b = RoomCleanupReview.Row(id: "b", name: "B", bytes: 14, consequence: "", entryIDs: [], parentFolders: ["/b", "/shared"])
        var review = RoomCleanupReview(rows: [a, b], selected: ["a", "b"], store: true, allowed: ["/a", "/shared"])
        #expect(review.commit == .allow(1))
        review.toggle("a")
        #expect(review.allowed == ["/shared"] && review.commit == .allow(1))
        review.toggle("a")
        #expect(review.allowed == ["/shared"] && review.commit == .allow(2))
    }

    @Test func rowTicksOnlyAfterAllItemsAreSaved() {
        let first = UUID(), second = UUID()
        let row = RoomCleanupReview.Row(id: "one", name: "A", bytes: 7, consequence: "", entryIDs: [first, second], parentFolders: [])
        let review = RoomCleanupReview(rows: [row], selected: ["one"], store: false)
        #expect(review.tickedRows(reported: [first]).isEmpty)
        #expect(review.tickedRows(reported: [first, second]) == ["one"])
    }

    @Test func movingDisablesCancelAndToggling() {
        let row = RoomCleanupReview.Row(id: "one", name: "A", bytes: 7, consequence: "", entryIDs: [], parentFolders: [])
        var review = RoomCleanupReview(rows: [row], selected: ["one"], store: false, phase: .moving)
        review.toggle("one")
        #expect(review.selected == ["one"] && !review.canCancel && !review.canCommit)
    }
}
