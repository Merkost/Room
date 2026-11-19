import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@MainActor struct RoomMakeRoomStoreTests {
    @Test func unreadableCapacityHasNoBaselineAndLedgerSurvivesRelaunch() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("RoomLedger-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("cache", isDirectory: true)
        let trash = directory.appendingPathComponent("fixture-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: cache.appendingPathComponent("loose-file"))
        let configuration = CacheConfiguration(roots: [.init(id: "fixture", title: "Fixture", subtitle: "", symbol: "archivebox",
            category: "developer", url: cache, consequence: "Can rebuild", minimumAge: 0)], homeDirectory: directory)
        let engine = CacheEngine(configuration: configuration, activityDirectory: directory.appendingPathComponent("activity"),
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: { original in
                let destination = trash.appendingPathComponent(original.lastPathComponent)
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            })
        let state = RoomStateStore(directory: directory.appendingPathComponent("State"))
        let ledger = RoomMakeRoomStore(state: state, home: directory, sample: { nil })
        let report = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        await ledger.recordMove(receipt: receipt)
        #expect(ledger.latest?.freeAtMove == nil && ledger.summary.madeBytes == 0)
        let relaunched = RoomMakeRoomStore(state: state, home: directory, sample: { nil })
        await relaunched.updateReceipts([receipt])
        #expect(relaunched.entries == ledger.entries)
        #expect(await state.load([RoomMakeRoomEntry].self, from: .ledger).value == ledger.entries)
    }
}
