import Foundation
import Testing
@testable import RoomCore

struct RoomMakeRoomLedgerTests {
    private let now = Date(timeIntervalSince1970: 50_000)
    private let device: UInt64 = 11
    private let free: Int64 = 1_000_000_000

    @Test func onlyObservedSameVolumeRiseAtTheThresholdIsAttributed() throws {
        let entry = try stageOne(bytes: 600_000_000)
        let advanced = try after(entry, freeGain: 300_000_000)
        #expect(advanced.stage == .emptied && advanced.observedGain == 300_000_000)
        let differentVolume = try after(entry, freeGain: 5_000_000_000, device: 12)
        #expect(differentVolume.observedGain == 0)
        #expect(differentVolume.stage == .emptiedNoGain)
    }

    @Test func noiseSmallMovesAndLongGapsNeverCreditGain() throws {
        let small = try stageOne(bytes: 200_000_000)
        let larger = try stageOne(bytes: 600_000_000)
        #expect(try after(small, freeGain: 500_000_000).observedGain == 0)
        #expect(try after(larger, freeGain: 200_000_000).observedGain == 0)
        let old = try after(larger, freeGain: 600_000_000, afterSeconds: 601)
        #expect(old.observedGain == 0 && old.attributionUncertain)
    }

    @Test func absentSamplesAndUnknownObservationsPreserveEvidence() throws {
        let entry = try stageOne(bytes: 600_000_000)
        let later = now.addingTimeInterval(60)
        let reading = RoomCapacitySample(freeBytes: free, device: device, at: later)
        let gone = RoomTrashObservation(presentBytes: 0, goneBytes: entry.movedBytes, restoredBytes: 0, canObserve: true)
        #expect(RoomMakeRoomLedger.advance([entry], observations: [:], sample: reading, now: later) == [entry])
        #expect(RoomMakeRoomLedger.advance([entry], observations: [entry.id: gone], sample: nil, now: later) == [entry])
    }

    @Test func adoptedReceiptsNeverBecomeMade() throws {
        let entry = try #require(RoomMakeRoomEntry.adopted(receiptID: UUID(), movedAt: now, movedBytes: 600_000_000, itemCount: 1))
        let result = try after(entry, freeGain: 600_000_000)
        #expect(result.stage == .emptiedNoGain && result.observedGain == 0)
        #expect(RoomMakeRoomCopy.headline(result, format: String.init) == "Gone from Trash")
        #expect(RoomHistorySummary.make([result]).madeCount == 0)
    }

    @Test func observationFailsClosedIfOneItemIsUnknown() {
        let observation = RoomTrashPresence.observation([(30, .present), (70, .unknown)])
        #expect(observation == nil)
        let unobservable = RoomTrashPresence.observation([(30, .present), (70, .unobservable)])
        #expect(unobservable?.canObserve == false)
    }

    private func stageOne(bytes: Int64) throws -> RoomMakeRoomEntry {
        try #require(RoomMakeRoomEntry.stageOne(receiptID: UUID(), movedAt: now, movedBytes: bytes, itemCount: 1,
            itemsDevice: device, sample: RoomCapacitySample(freeBytes: free, device: device, at: now)))
    }

    private func after(_ entry: RoomMakeRoomEntry, freeGain: Int64, device: UInt64 = 11,
                       afterSeconds: TimeInterval = 60) throws -> RoomMakeRoomEntry {
        let later = now.addingTimeInterval(afterSeconds)
        let sample = RoomCapacitySample(freeBytes: free + freeGain, device: device, at: later)
        let gone = RoomTrashObservation(presentBytes: 0, goneBytes: entry.movedBytes, restoredBytes: 0, canObserve: true)
        return try #require(RoomMakeRoomLedger.advance([entry], observations: [entry.id: gone], sample: sample, now: later).first)
    }
}
