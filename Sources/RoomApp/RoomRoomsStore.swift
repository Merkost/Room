import Foundation

nonisolated struct RoomPinnedRoom: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var accessFolderID: String
    var name: String
    var order: Int
}

/// Room references and size history stay in the app's own Application Support directory.
/// Security-scoped bookmarks remain exclusively in RoomFileAccess.
@MainActor
struct RoomRoomsStore {
    static let maximumRooms = 64
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Room/State", isDirectory: true)
    }

    let directory: URL

    init(directory: URL = RoomRoomsStore.defaultDirectory) { self.directory = directory }

    func loadRooms() -> [RoomPinnedRoom] {
        normalized(read([RoomPinnedRoom].self, name: "rooms.json") ?? [])
    }

    func loadSizes() -> [String: RoomSizeLog] {
        normalized(read([String: RoomSizeLog].self, name: "room-sizes.json") ?? [:])
    }

    @discardableResult
    func saveRooms(_ rooms: [RoomPinnedRoom]) -> Bool { write(normalized(rooms), name: "rooms.json") }

    @discardableResult
    func saveSizes(_ sizes: [String: RoomSizeLog]) -> Bool { write(normalized(sizes), name: "room-sizes.json") }

    private func normalized(_ rooms: [RoomPinnedRoom]) -> [RoomPinnedRoom] {
        var ids: Set<UUID> = []
        return Array(rooms.sorted {
            $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
        }.filter { ids.insert($0.id).inserted }.prefix(Self.maximumRooms))
    }

    private func normalized(_ sizes: [String: RoomSizeLog]) -> [String: RoomSizeLog] {
        Dictionary(uniqueKeysWithValues: sizes.keys.sorted().filter { UUID(uuidString: $0) != nil }
            .prefix(Self.maximumRooms).compactMap { key in sizes[key].map { (key, $0) } })
    }

    private func read<Value: Decodable>(_ type: Value.Type, name: String) -> Value? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<Value: Encodable>(_ value: Value, name: String) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return true
        } catch { return false }
    }
}
