import Foundation
import Testing
@testable import RoomApp

@Suite("Pinned Room persistence") @MainActor
struct RoomRoomsStoreTests {
    @Test func roomsAndDailySizesSurviveRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomRoomsStore(directory: directory)
        let room = RoomPinnedRoom(id: UUID(), accessFolderID: "approved-folder", name: "Work", order: 0)
        var log = RoomSizeLog()
        log.record(RoomSizePoint(at: Date(timeIntervalSince1970: 1_794_876_000), bytes: 74_300_000_000, partial: false), calendar: .current)
        #expect(store.saveRooms([room]))
        #expect(store.saveSizes([room.id.uuidString: log]))
        let reloaded = RoomRoomsStore(directory: directory)
        #expect(reloaded.loadRooms() == [room])
        #expect(reloaded.loadSizes() == [room.id.uuidString: log])
        let data = try Data(contentsOf: directory.appendingPathComponent("room-sizes.json"))
        let envelope = try RoomStateCodec.decoder().decode(RoomStoredFile<[String: RoomSizeLog]>.self, from: data)
        #expect(envelope.payload[room.id.uuidString] == log)
        #expect(!String(decoding: try Data(contentsOf: directory.appendingPathComponent("rooms.json")), as: UTF8.self).contains("bookmark"))
    }

    @Test func missingAndDamagedFilesStartEmptyIndependently() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomRoomsStore(directory: directory)
        #expect(store.loadRooms().isEmpty && store.loadSizes().isEmpty)
        let room = RoomPinnedRoom(id: UUID(), accessFolderID: "access", name: "Work", order: 0)
        #expect(store.saveRooms([room]))
        try Data("damaged".utf8).write(to: directory.appendingPathComponent("room-sizes.json"))
        #expect(store.loadRooms() == [room] && store.loadSizes().isEmpty)
        try Data("damaged".utf8).write(to: directory.appendingPathComponent("rooms.json"))
        #expect(store.loadRooms().isEmpty)
    }

    @Test func legacyFileDecodesAndOneDamagedEntryKeepsOthers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rooms.json")
        let payload = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","accessFolderID":"f1","name":"Work","order":0},{"id":"bad"},{"id":"00000000-0000-0000-0000-000000000002","accessFolderID":"f2","name":"Photos","order":1,"glyph":"photo"}]"#.utf8)
        try payload.write(to: file)
        let store = RoomRoomsStore(directory: directory)
        #expect(store.loadRooms().map(\.name) == ["Work", "Photos"])
        #expect(store.loadRooms().map(\.resolvedGlyph) == [.folder, .photo])
        #expect(try Data(contentsOf: file) == payload)
    }

    @Test func failedReadNeverWritesEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rooms.json")
        let payload = Data("damage".utf8)
        try payload.write(to: file)
        let store = RoomRoomsStore(directory: directory)
        #expect(store.loadRooms().isEmpty)
        #expect(try Data(contentsOf: file) == payload)
    }

    @Test func roomArrayIsOrderedUniqueAndLimitedTo64() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomRoomsStore(directory: directory)
        let rooms = (0..<70).map { RoomPinnedRoom(id: UUID(), accessFolderID: "access-\($0)", name: "Room \($0)", order: $0) }
        #expect(store.saveRooms(Array(rooms.reversed()) + [rooms[0]]))
        #expect(store.loadRooms() == Array(rooms.prefix(64)))
    }

    @Test func persistenceFailureDoesNotThrowOrDestroyExistingData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("keep".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomRoomsStore(directory: directory)
        #expect(!store.saveRooms([]))
        #expect(!store.saveSizes([:]))
        #expect(try Data(contentsOf: directory) == Data("keep".utf8))
    }

    @Test func defaultDirectoryUsesApplicationSupportState() throws {
        let support = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        #expect(RoomRoomsStore.defaultDirectory == support.appendingPathComponent("Room/State", isDirectory: true))
    }
}
