import Foundation
import Testing
@testable import RoomApp

struct RoomStateStoreTests {
    private static let fixed = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func legacyRoomsRewrittenOnce() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let room = RoomPinnedRoom(id: UUID(), accessFolderID: "grant", name: "Work", order: 0)
        let destination = directory.appendingPathComponent(RoomStateFile.rooms.name)
        try JSONEncoder().encode([room]).write(to: destination)
        let store = RoomStateStore(directory: directory, appVersion: "test", now: { Self.fixed })

        let first = await store.load([RoomPinnedRoom].self, from: .rooms, legacy: {
            try JSONDecoder().decode([RoomPinnedRoom].self, from: $0)
        })
        guard case let .loaded(rooms, rewrite: false) = first else {
            Issue.record("Legacy data should be migrated once")
            return
        }
        #expect(rooms == [room])
        let bytes = try Data(contentsOf: destination)
        #expect(RoomStateCodec.classify(bytes, currentSchema: RoomStateFile.rooms.schema) == .current)
        let next = RoomStateStore(directory: directory, now: { Self.fixed.addingTimeInterval(80) })
        guard case let .loaded(saved, rewrite: false) = await next.load([RoomPinnedRoom].self, from: .rooms),
              saved == [room] else {
            Issue.record("Relaunch could not read the written envelope")
            return
        }
        #expect(try Data(contentsOf: destination) == bytes)
    }

    @Test func atomicReplaceKeepsOldOnFailure() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent(RoomStateFile.rooms.name)
        let old = try RoomStateCodec.encode(["old"], file: .rooms, writtenAt: Self.fixed, appVersion: "1")
        try old.write(to: destination)
        let disk = RoomFileStateDisk { temporary, _ in
            #expect(FileManager.default.fileExists(atPath: temporary.path))
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let store = RoomStateStore(directory: directory, disk: disk)
        await #expect(throws: CocoaError.self) {
            try await store.write(["new"], to: .rooms, generation: 1)
        }
        #expect(try Data(contentsOf: destination) == old)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [RoomStateFile.rooms.name])
    }

    @Test func newerSchemaNeverOverwritten() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let future = RoomStateFile(name: RoomStateFile.rooms.name, schema: RoomStateFile.rooms.schema + 1, maxBytes: 128_000, survivesForget: true)
        let bytes = try RoomStateCodec.encode(["future"], file: future, writtenAt: Self.fixed, appVersion: "3")
        let destination = directory.appendingPathComponent(future.name)
        try bytes.write(to: destination)
        let store = RoomStateStore(directory: directory)
        await #expect(throws: RoomStateError.readOnlyNewerSchema(future.name)) {
            try await store.write(["new"], to: .rooms, generation: 1)
        }
        if case let .newerReadOnly(value) = await store.load([String].self, from: .rooms) {
            #expect(value == ["future"])
        } else {
            Issue.record("A future file must be treated as read-only")
        }
        #expect(try Data(contentsOf: destination) == bytes)
    }

    @Test func damagedMovedAsideKeepThree() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent(RoomStateFile.rooms.name)
        let store = RoomStateStore(directory: directory, now: { Self.fixed })
        for _ in 0..<4 {
            try Data("{".utf8).write(to: destination)
            guard case .damaged = await store.load([String].self, from: .rooms) else {
                Issue.record("Invalid JSON should be classed as damaged")
                return
            }
        }
        let removed = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Damaged").path)
        #expect(removed.count == 3)
        #expect(!removed.contains(RoomStateDamaged.name(for: .rooms, at: Self.fixed)))
        #expect(await store.damagedFileNames == [RoomStateFile.rooms.name])
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func staleGenerationDropped() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomStateStore(directory: directory)
        try await store.write(["latest"], to: .rooms, generation: 4)
        try await store.write(["old"], to: .rooms, generation: 2)
        try await store.write(["duplicate"], to: .rooms, generation: 4)
        guard case let .loaded(value, _) = await store.load([String].self, from: .rooms) else {
            Issue.record("Expected persisted value")
            return
        }
        #expect(value == ["latest"])
    }

    @Test func oversizedRefused() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = RoomStateFile(name: "small.json", schema: 1, maxBytes: 80, survivesForget: false)
        let store = RoomStateStore(directory: directory)
        await #expect(throws: RoomStateError.self) {
            try await store.write(String(repeating: "a", count: 200), to: file, generation: 1)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(file.name).path))
    }

    @Test func directory0700Files0600() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomStateStore(directory: directory)
        let tree = RoomStateFile.tree(rootID: "test")
        try await store.write(["one"], to: tree, generation: 1)
        try await store.write(["two"], to: tree, generation: 2)
        let attributes = FileManager.default.attributesOfItem(atPath:)
        #expect(try attributes(directory.path)[.posixPermissions] as? Int == 0o700)
        #expect(try attributes(directory.appendingPathComponent("trees").path)[.posixPermissions] as? Int == 0o700)
        #expect(try attributes(directory.appendingPathComponent(tree.name).path)[.posixPermissions] as? Int == 0o600)
    }

    @Test @MainActor func flushWithinDeadline() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomStateStore(directory: directory)
        let writer = RoomStateWriter(store: store, debounce: .seconds(60))
        writer.submit(["first"], to: .rooms)
        writer.submit(["second"], to: .rooms)
        writer.submit(["sizes"], to: .roomSizes)
        #expect(writer.hasPendingWrites)
        await writer.flush(deadline: .seconds(1))
        #expect(!writer.hasPendingWrites)
        guard case let .loaded(rooms, _) = await store.load([String].self, from: .rooms),
              case let .loaded(sizes, _) = await store.load([String].self, from: .roomSizes) else {
            Issue.record("Flush must write both pending concerns")
            return
        }
        #expect(rooms == ["second"] && sizes == ["sizes"])
    }
}

func reserveStateFixture() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("room-state-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
}
