import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

struct RoomHistorySummaryTests {
    @Test func aboutNeverCountsMovedBytesAsMade() throws {
        let time = Date(timeIntervalSince1970: 40)
        let moved = try #require(RoomMakeRoomEntry.adopted(receiptID: UUID(), movedAt: time, movedBytes: 800_000_000, itemCount: 1))
        let summary = RoomHistorySummary.make([moved])
        #expect(summary.madeCount == 0 && summary.madeBytes == 0)
        #expect(summary.header(format: String.init, month: { _ in "March" }) == "Moved 800000000 to Trash that is still there")

        var made = moved
        made.stage = .emptied
        made.observedGain = 500_000_000
        made.goneBytes = made.movedBytes
        let observed = RoomHistorySummary.make([moved, made])
        #expect(observed.madeCount == 1 && observed.madeBytes == 500_000_000 && observed.badge == 1)
    }

    @Test func commandYAppearsOnlyForMainWindow() throws {
        let active = RoomMenuModel.make(.init(destination: .overview, window: .main))
        let history = try #require(active.first { $0.id == .showHistory })
        #expect(history.enabled && history.shortcut == .init("y"))
        let modal = RoomMenuModel.make(.init(destination: .overview, window: .modal))
        #expect(modal.first { $0.id == .showHistory }?.enabled == false)
        #expect(RoomMenuModel.Destination(rawValue: "activity") == nil)
    }
}
