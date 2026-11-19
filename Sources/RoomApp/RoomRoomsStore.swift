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
        let roomResult = await writer.store.load([RoomPinnedRoom].self, from: .rooms, legacy: Self.decodeLegacyRooms)
        let sizeResult = await writer.store.load([String: RoomSizeLog].self, from: .roomSizes, legacy: Self.decodeLegacySizes)
        let rooms = normalized(roomResult.value ?? [])
        let sizes = normalized(sizeResult.value ?? [:])
        return (rooms, sizes, roomResult.isReadOnly)
    }

    func discardPendingSizes() { writer?.discardPending(for: .roomSizes) }

    func loadRooms() -> [RoomPinnedRoom] {
        normalized(read([RoomPinnedRoom].self, file: .rooms, legacy: Self.decodeLegacyRooms) ?? [])
    }

    func loadSizes() -> [String: RoomSizeLog] {
        normalized(read([String: RoomSizeLog].self, file: .roomSizes, legacy: Self.decodeLegacySizes) ?? [:])
    }

    @discardableResult
    func saveRooms(_ rooms: [RoomPinnedRoom]) -> Bool { write(normalized(rooms), file: .rooms) }

    @discardableResult
    func saveSizes(_ sizes: [String: RoomSizeLog]) -> Bool { write(normalized(sizes), file: .roomSizes) }

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

    nonisolated private static func decodeLegacyRooms(_ bytes: Data) throws -> [RoomPinnedRoom] {
        try JSONDecoder().decode([RoomPinnedRoom].self, from: bytes)
    }

    nonisolated private static func decodeLegacySizes(_ bytes: Data) throws -> [String: RoomSizeLog] {
        try JSONDecoder().decode([String: RoomSizeLog].self, from: bytes)
    }

    private func read<Value: Codable & Sendable>(_ type: Value.Type, file: RoomStateFile,
                                                 legacy: @escaping (Data) throws -> Value) -> Value? {
        let url = directory.appendingPathComponent(file.name)
        guard let data = try? RoomFileStateDisk().read(url, maximumBytes: file.maxBytes) else { return nil }
        return RoomStateCodec.decode(data, as: type, file: file, legacy: legacy).value
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
