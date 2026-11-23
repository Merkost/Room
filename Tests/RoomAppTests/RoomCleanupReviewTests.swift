import Foundation
import Testing
@testable import RoomApp

struct RoomCleanupReviewTests {
    @Test func indexedMapLookupMatchesSelectionBoundaries() {
        let entries = ["/cache-backup/a", "/cache/子/a", "/cache/file", "/cache/child-sibling/a", "/cache/child/z",
                       "/unicode/\u{0301}early", "/unicode/子", "/accent-only/\u{0301}early", "/café/entry"]
            .map { URL(fileURLWithPath: $0) }
        let index = RoomMapCleanupPathIndex(entries.map(\.path))
        let probes = ["/", "/cache", "/cache/子", "/cache/file", "/cache/child", "/cache/child-sib",
                      "/cache/other", "/cache-b", "/missing", "/unicode", "/accent-only", "/cafe\u{0301}"]
        for path in probes {
            for includesContents in [false, true] {
                let expected = entries.contains { RoomMapCleanup.matches($0, path: path, includesContents: includesContents) }
                #expect(index.contains(path: path, includesContents: includesContents) == expected)
            }
        }
        #expect(!RoomMapCleanupPathIndex([]).contains(path: "/", includesContents: true))
    }

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
