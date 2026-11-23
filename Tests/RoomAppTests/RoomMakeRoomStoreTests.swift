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

    private static func receipt(bytes: Int64 = 600_000_000, date: Date = Date()) -> ActivityReceipt {
        let identity = FileIdentity(device: 1, inode: 2, modifiedSeconds: 0, modifiedNanoseconds: 0,
            changedSeconds: 0, changedNanoseconds: 0, byteCount: bytes, mode: 0o100600)
        let item = ActivityItem(id: UUID(), rootID: "r", originalURL: URL(fileURLWithPath: "/tmp/x"), trashURL: nil,
            byteCount: bytes, originalIdentity: identity, rootIdentity: identity, trashIdentity: nil, trashFingerprint: nil,
            status: .trashed, message: nil, originalParentIdentity: nil)
        return ActivityReceipt(id: UUID(), date: date, items: [item], issues: [])
    }

    private static func oldClosed(_ receipt: ActivityReceipt, now: Date) -> RoomMakeRoomEntry {
        var entry = RoomMakeRoomEntry.adopted(receiptID: UUID(), movedAt: now.addingTimeInterval(-200 * 86_400),
            movedBytes: receipt.trashedBytes, itemCount: 1)!
        entry.stage = .emptiedNoGain
        entry.closed = true
        return entry
    }

    @Test func overTheCapLedgerIsPrunedBeforeSavingAndKeepsOpenEntries() async throws {
        let directory = Self.temp()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        let now = Date()
        let template = Self.receipt()
        let old = (0..<500).map { _ in Self.oldClosed(template, now: now) }
        try await state.write(old, to: .ledger, generation: 0)
        let fresh = (0..<500).map { _ in Self.receipt(date: now) }
        let store = RoomMakeRoomStore(state: state, home: directory, sample: { nil })
        await store.updateReceipts(fresh)
        #expect(!store.hadWriteFailure, "\(store.writeFailureMessage ?? "")")
        #expect(store.entries.count == 500 && store.entries.allSatisfy { !$0.closed })
        let persisted = try #require(await state.load([RoomMakeRoomEntry].self, from: .ledger).value)
        #expect(Set(persisted.map(\.id)) == Set(fresh.map(\.id)))
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
