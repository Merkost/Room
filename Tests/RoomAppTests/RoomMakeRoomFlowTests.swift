import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@MainActor
struct RoomMakeRoomFlowTests {
    @Test func reviewSheetAsksWithTheChosenTotal() {
        #expect(RoomReviewWords.title(22_400_000_000, hidden: false) == "Move 22 GB to Trash?")
        #expect(!RoomReviewWords.title(22_400_000_000, hidden: true).contains("22"), "Hide masks the sheet's size")
        #expect(RoomReviewWords.body(.caches).contains("History can put"))
        #expect(RoomReviewWords.body(.ownFolders).hasPrefix("These are your own folders, not caches."))
    }

    @Test func reviewTotalsFollowTheTicks() {
        let a = RoomCleanupReview.Row(id: "a", name: "npm", bytes: 4_000_000_000, consequence: "", entryIDs: [UUID()], parentFolders: [])
        let b = RoomCleanupReview.Row(id: "b", name: "Gradle", bytes: 3_000_000_000, consequence: "", entryIDs: [UUID()], parentFolders: [])
        let both = RoomCleanupReview(rows: [a, b], selected: ["a", "b"], store: false)
        #expect(both.selectedBytes == 7_000_000_000)
        #expect(both.commit == .move(7_000_000_000))
        let one = RoomCleanupReview(rows: [a, b], selected: ["b"], store: false)
        #expect(one.selectedBytes == 3_000_000_000)
        #expect(RoomCleanupReview(rows: [a, b], selected: [], store: false).commit == .selectAtLeastOne)
    }

    @Test func progressCountsFinishedItems() {
        let ids = (0..<4).map { _ in UUID() }
        let statuses: [UUID: ActivityStatus] = [ids[0]: .trashed, ids[1]: .failed, ids[2]: .pending, ids[3]: .pending]
        #expect(RoomMakeRoomProgress.counts(statuses) == (2, 4))
        #expect(RoomMakeRoomProgress.movedBytes(statuses, totalBytes: 22_000_000_000) == 11_000_000_000)
        #expect(RoomMakeRoomProgress.failed(statuses) == 1)
        #expect(RoomMakeRoomProgress.movedBytes([:], totalBytes: 22) == 0)
    }

    @Test func toastSaysMadeThenPutBack() {
        var toast = RoomMadeToastState(receiptID: UUID(), bytes: 22_000_000_000)
        #expect(toast.text == "Made 22 GB")
        toast.restored = true
        #expect(toast.text == "Put back")
    }

    @Test func overviewRowCountsTheMoveAndEndsWithMade() {
        var row = RoomRowActivity()
        let t0 = Date()
        row.apply(RoomRowSignals.makeRoom(isMoving: true, movedBytes: 7_000_000_000, totalBytes: 22_000_000_000,
                                          madeBytes: nil, failed: 0), isOpen: true, now: t0)
        #expect(row.sentence == "Moving 7 of 22 GB")
        #expect(row.dots?.total == 12)
        row.apply(RoomRowSignals.makeRoom(isMoving: false, movedBytes: 0, totalBytes: 22_000_000_000,
                                          madeBytes: 22_000_000_000, failed: 0), isOpen: true, now: t0)
        #expect(row.showsCheck && row.sentence == "Made 22 GB")
    }
}
