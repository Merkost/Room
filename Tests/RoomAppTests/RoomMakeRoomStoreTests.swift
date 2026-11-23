import Foundation
import Synchronization
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
        let restored = try #require(relaunched.latest)
        #expect(restored.id == receipt.id && restored.movedBytes == receipt.trashedBytes)
        #expect(restored.freeAtMove == nil && restored.observedGain == 0)
        #expect(abs(restored.movedAt.timeIntervalSince(receipt.date)) < 1)
        let persisted = await state.load([RoomMakeRoomEntry].self, from: .ledger).value
        #expect(persisted == relaunched.entries)
    }

    private static func temp() -> URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("RoomLedger-\(UUID())")
    }

    private static func receipt(id: UUID = UUID(), bytes: Int64 = 600_000_000, date: Date = Date(),
                                status: ActivityStatus = .trashed) -> ActivityReceipt {
        let identity = FileIdentity(device: 1, inode: 2, modifiedSeconds: 0, modifiedNanoseconds: 0,
            changedSeconds: 0, changedNanoseconds: 0, byteCount: bytes, mode: 0o100600)
        let item = ActivityItem(id: UUID(), rootID: "r", originalURL: URL(fileURLWithPath: "/tmp/x"), trashURL: nil,
            byteCount: bytes, originalIdentity: identity, rootIdentity: identity, trashIdentity: nil, trashFingerprint: nil,
            status: status, message: nil, originalParentIdentity: nil)
        return ActivityReceipt(id: id, date: date, items: [item], issues: [])
    }

    private static func oldClosed(_ receipt: ActivityReceipt, now: Date) -> RoomMakeRoomEntry {
        var entry = RoomMakeRoomEntry.adopted(receiptID: UUID(), movedAt: now.addingTimeInterval(-200 * 86_400),
            movedBytes: receipt.trashedBytes, itemCount: 1)!
        entry.stage = .emptiedNoGain
        entry.closed = true
        return entry
    }

    /// Old closed entries and their receipts. A receipt that can still restore keeps its entry, so the first read
    /// reports them restored (prunable); the second reads the same ids as trashed again, as a reloaded history would.
    private static func oldPairs(count: Int, now: Date, gain: Int64 = 0) -> (entries: [RoomMakeRoomEntry],
        restored: [ActivityReceipt], trashed: [ActivityReceipt]) {
        var entries: [RoomMakeRoomEntry] = [], restored: [ActivityReceipt] = [], trashed: [ActivityReceipt] = []
        for _ in 0..<count {
            let id = UUID()
            let date = now.addingTimeInterval(-200 * 86_400)
            var entry = RoomMakeRoomEntry.adopted(receiptID: id, movedAt: date, movedBytes: 600_000_000, itemCount: 1)!
            entry.stage = gain > 0 ? .emptied : .emptiedNoGain
            entry.observedGain = gain
            entry.closed = true
            entries.append(entry)
            restored.append(Self.receipt(id: id, date: date, status: .restored))
            trashed.append(Self.receipt(id: id, date: date))
        }
        return (entries, restored, trashed)
    }

    @Test func overTheCapLedgerIsPrunedBeforeSavingAndKeepsOpenEntries() async throws {
        let directory = Self.temp()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        let now = Date()
        let old = Self.oldPairs(count: 500, now: now)
        try await state.write(old.entries, to: .ledger, generation: 0)
        let fresh = (0..<500).map { _ in Self.receipt(date: now) }
        let history = old.restored + fresh
        let store = RoomMakeRoomStore(state: state, home: directory, sample: { nil })
        await store.updateReceipts(history)
        #expect(!store.hadWriteFailure, "\(store.writeFailureMessage ?? "")")
        #expect(store.entries.count == 500 && store.entries.allSatisfy { !$0.closed })
        let madeBefore = store.summary.madeBytes
        await store.updateReceipts(old.trashed + fresh)
        #expect(store.entries.count == 500, "pruned entries must not regrow from their receipts")
        #expect(store.summary.madeBytes == madeBefore)
        let persisted = try #require(await state.load([RoomMakeRoomEntry].self, from: .ledger).value)
        #expect(Set(persisted.map(\.id)) == Set(fresh.map(\.id)))
    }

    @Test func prunedEntriesAreNotRecreatedFromReceipts() async throws {
        let directory = Self.temp()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        let old = Self.oldPairs(count: 5, now: Date())
        try await state.write(old.entries, to: .ledger, generation: 0)
        let store = RoomMakeRoomStore(state: state, home: directory, sample: { nil })
        let fresh = Self.receipt(date: Date())
        await store.updateReceipts(old.restored + [fresh])
        #expect(store.entries.map(\.id) == [fresh.id], "a new entry triggers the save that prunes")
        await store.updateReceipts(old.trashed + [fresh])
        #expect(store.entries.map(\.id) == [fresh.id])
        let relaunched = RoomMakeRoomStore(state: state, home: directory, sample: { nil })
        await relaunched.updateReceipts(old.trashed + [fresh])
        #expect(relaunched.entries.map(\.id) == [fresh.id], "the pruned ids survive a relaunch")
    }

    @Test func observedGainEntriesAreNeverPruned() async throws {
        let directory = Self.temp()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        let old = Self.oldPairs(count: 3, now: Date(), gain: 500_000_000)
        try await state.write(old.entries, to: .ledger, generation: 0)
        let store = RoomMakeRoomStore(state: state, home: directory, sample: { nil })
        await store.updateReceipts(old.restored + [Self.receipt(date: Date())])
        #expect(store.entries.count == 4)
        #expect(store.summary.madeBytes == 1_500_000_000)
    }

    @Test func aFailedWriteAfterASuccessfulOneIsSurfacedThenClears() async throws {
        let directory = Self.temp()
        defer { try? FileManager.default.removeItem(at: directory) }
        struct Refused: Error {}
        let refuse = Mutex(false)
        let state = RoomStateStore(directory: directory, disk: RoomFileStateDisk(beforeSwap: { _, _ in
            if refuse.withLock({ $0 }) { throw Refused() }
        }))
        let store = RoomMakeRoomStore(state: state, home: directory, sample: { nil })
        await store.recordMove(receipt: Self.receipt())
        #expect(!store.hadWriteFailure && store.writeFailureMessage == nil)
        refuse.withLock { $0 = true }
        await store.recordMove(receipt: Self.receipt())
        #expect(store.hadWriteFailure && store.writeFailureMessage != nil)
        refuse.withLock { $0 = false }
        await store.recordMove(receipt: Self.receipt())
        #expect(!store.hadWriteFailure && store.writeFailureMessage == nil)
    }

    @Test func overlappingChecksTakeOnlyOneSample() async throws {
        let directory = Self.temp()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = Mutex(0)
        let store = RoomMakeRoomStore(state: RoomStateStore(directory: directory), home: directory, sample: {
            calls.withLock { $0 += 1 }
            try? await Task.sleep(for: .milliseconds(150))
            return nil
        })
        await store.updateReceipts([Self.receipt()])
        async let first: Void = store.checkNow()
        async let second: Void = store.checkNow()
        _ = await (first, second)
        #expect(calls.withLock { $0 } == 1)
    }
}
