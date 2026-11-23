#if DEBUG
import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@MainActor struct RoomDebugTrashSimulatorTests {
    @Test func simulationNeverWritesLedgerFileAndResetRestoresRealEntries() async throws {
        let time = Date(timeIntervalSince1970: 10_000)
        let entry = try #require(RoomMakeRoomEntry.stageOne(receiptID: UUID(), movedAt: time,
            movedBytes: 600_000_000, itemCount: 2, itemsDevice: 5, sample: .init(freeBytes: 1_000_000_000, device: 5, at: time)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RoomSimulatedTrash-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        try await state.write([entry], to: .ledger, generation: 1)
        let url = directory.appendingPathComponent(RoomStateFile.ledger.name)
        let before = try Data(contentsOf: url)
        let ledger = RoomMakeRoomStore(state: state, home: directory, sample: { nil })

        await ledger.simulateTrash(at: time.addingTimeInterval(60))
        let virtual = try #require(ledger.latest)
        #expect(virtual.observedGain == 600_000_000)
        #expect(RoomMakeRoomCopy.headline(virtual, format: String.init) == "Made 600000000 of room")
        #expect(try Data(contentsOf: url) == before)
        ledger.resetSimulatedTrash()
        #expect(ledger.entries == [entry])
    }
}
#endif
