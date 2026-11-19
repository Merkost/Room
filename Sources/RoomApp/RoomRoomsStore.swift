import Foundation

nonisolated struct RoomPinnedRoom: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var accessFolderID: String
    var name: String
    var order: Int
    var glyph: String? = nil
    var colour: String? = nil
    var budgetBytes: Int64? = nil

    var resolvedGlyph: RoomRoomGlyph { glyph.flatMap(RoomRoomGlyph.init(rawValue:)) ?? .folder }
    var resolvedColour: RoomRoomColour { colour.flatMap(RoomRoomColour.init(rawValue:)) ?? .developer }
}

/// Room references and size history stay in the app's own Application Support directory.
/// Security-scoped bookmarks remain exclusively in RoomFileAccess.
@MainActor
struct RoomRoomsStore {
    static let maximumRooms = RoomRoomsCatalog.maximumRooms
    static var defaultDirectory: URL { RoomStateStore.defaultDirectory }

    let directory: URL
    private let writer: RoomStateWriter?
    var loadsAsynchronously: Bool { writer != nil }

    init(writer: RoomStateWriter = .shared) {
        self.writer = writer
        directory = writer.store.directory
    }

    /// Isolated directories also support synchronous reads and writes for existing fixture clients.
    init(directory: URL) {
        self.directory = directory
        writer = nil
    }

    func loadState() async -> (rooms: [RoomPinnedRoom], sizes: [String: RoomSizeLog], readOnly: Bool) {
        guard let writer else { return (loadRooms(), loadSizes(), false) }
        let roomResult = await writer.store.load([RoomPinnedRoom].self, from: .rooms, legacy: Self.decodeLegacyRooms, migrate: Self.migrateRooms)
        let sizeResult = await writer.store.load([String: RoomSizeLog].self, from: .roomSizes, legacy: Self.decodeLegacySizes)
        let rooms = normalized(roomResult.value ?? [])
        let sizes = normalized(sizeResult.value ?? [:])
        return (rooms, sizes, roomResult.isReadOnly)
    }

    func discardPendingSizes() { writer?.discardPending(for: .roomSizes) }

    func loadRooms() -> [RoomPinnedRoom] {
        normalized(read([RoomPinnedRoom].self, file: .rooms, legacy: Self.decodeLegacyRooms, migrate: Self.migrateRooms) ?? [])
    }

    func loadSizes() -> [String: RoomSizeLog] {
        normalized(read([String: RoomSizeLog].self, file: .roomSizes, legacy: Self.decodeLegacySizes) ?? [:])
    }

    @discardableResult
    func saveRooms(_ rooms: [RoomPinnedRoom]) -> Bool { write(normalized(rooms), file: .rooms) }

    @discardableResult
    func saveSizes(_ sizes: [String: RoomSizeLog]) -> Bool { write(normalized(sizes), file: .roomSizes) }

    private func normalized(_ rooms: [RoomPinnedRoom]) -> [RoomPinnedRoom] {
        RoomRoomsCatalog.normalized(rooms)
    }

    private func normalized(_ sizes: [String: RoomSizeLog]) -> [String: RoomSizeLog] {
        Dictionary(uniqueKeysWithValues: sizes.keys.sorted().filter { UUID(uuidString: $0) != nil }
            .prefix(Self.maximumRooms).compactMap { key in sizes[key].map { (key, $0) } })
    }

    nonisolated private static func decodeLegacyRooms(_ bytes: Data) throws -> [RoomPinnedRoom] {
        guard let rooms = RoomRoomsDecoding.rooms(from: bytes) else { throw CocoaError(.fileReadCorruptFile) }
        return rooms
    }

    nonisolated private static func migrateRooms(_ schema: Int, _ data: Data) throws -> [RoomPinnedRoom] {
        guard schema == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return try decodeLegacyRooms(data)
    }

    nonisolated private static func decodeLegacySizes(_ bytes: Data) throws -> [String: RoomSizeLog] {
        try JSONDecoder().decode([String: RoomSizeLog].self, from: bytes)
    }

    private func read<Value: Codable & Sendable>(_ type: Value.Type, file: RoomStateFile,
                                                 legacy: @escaping (Data) throws -> Value,
                                                 migrate: ((Int, Data) throws -> Value)? = nil) -> Value? {
        let url = directory.appendingPathComponent(file.name)
        guard let data = try? RoomFileStateDisk().read(url, maximumBytes: file.maxBytes) else { return nil }
        return RoomStateCodec.decode(data, as: type, file: file, legacy: legacy, migrate: migrate).value
    }

    private func write<Value: Codable & Sendable>(_ value: Value, file: RoomStateFile) -> Bool {
        if let writer {
            writer.submit(value, to: file)
            return true
        }
        do {
            let disk = RoomFileStateDisk()
            let url = directory.appendingPathComponent(file.name)
            if let old = try disk.read(url, maximumBytes: file.maxBytes),
               case .newer = RoomStateCodec.classify(old, currentSchema: file.schema) { return false }
            let data = try RoomStateCodec.encode(value, file: file, writtenAt: Date(), appVersion: "2.0")
            try disk.replace(data, at: url)
            return true
        } catch { return false }
    }
}
