import Foundation
import Observation
import RoomCore

/// The Disk Map's multi-select, kept pure: which rooms are ticked, their total and share, and which rooms can't be.
nonisolated struct RoomMapSelection: Equatable, Sendable {
    struct Room: Equatable, Sendable {
        let path: String          // relative to the map root
        let name: String
        let bytes: Int64
        let protection: FolderProtection?
    }

    private(set) var ticked: [String] = []    // relative paths, in tick order

    var isEmpty: Bool { ticked.isEmpty }
    var count: Int { ticked.count }

    /// Ticks or unticks a room. A protected room never ticks; the caller shows its sentence instead.
    @discardableResult
    mutating func toggle(_ room: Room) -> FolderProtection? {
        if let protection = room.protection { return protection }
        if let index = ticked.firstIndex(of: room.path) { ticked.remove(at: index) } else { ticked.append(room.path) }
        return nil
    }

    mutating func clear() { ticked.removeAll() }

    /// Keeps only ticks that are still rooms on this level (a rescan or a step elsewhere drops the rest).
    mutating func keep(only paths: Set<String>) { ticked.removeAll { !paths.contains($0) } }

    func contains(_ path: String) -> Bool { ticked.contains(path) }

    func bytes(in rooms: [Room]) -> Int64 {
        rooms.filter { ticked.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    /// "2 selected, 102 GB, 24% of your home".
    func line(in rooms: [Room], levelBytes: Int64, place: String) -> String {
        let total = bytes(in: rooms)
        let share = levelBytes > 0 ? Int((Double(total) / Double(levelBytes) * 100).rounded()) : 0
        return "\(count) selected, \(RoomFormat.gb(total)), \(share)% of \(place)"
    }
}

/// Disk Map folder moves for the window: the engine, its receipts, and the review in progress. Direct edition only;
/// the Store edition never offers the tick (see BUILD-DECISIONS, Store feasibility).
@Observable @MainActor
final class RoomFolderTrashModel {
    struct Review: Identifiable, Equatable {
        let id = UUID()
        let requests: [FolderTrashRequest]
        let names: [String]
        var bytes: Int64 { requests.reduce(0) { $0 + $1.bytes } }
    }

    static var isAvailable: Bool {
        #if ROOM_APP_STORE
        false
        #else
        true
        #endif
    }

    private(set) var receipts: [FolderTrashReceipt] = []
    private(set) var isMoving = false
    private(set) var lastMovedID: UUID?
    private(set) var message: String?
    @ObservationIgnored private let engine: FolderTrashEngine
    @ObservationIgnored let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath(),
         directory: URL? = nil, trash: (@Sendable (URL) throws -> URL)? = nil) {
        self.home = home
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Room/FolderReceipts", isDirectory: true)
        engine = FolderTrashEngine(home: home, directory: directory, trash: trash)
    }

    func load() async { receipts = await engine.history() }

    func protection(for url: URL?) -> FolderProtection? {
        guard Self.isAvailable else { return .unverified }
        guard let url else { return .unverified }
        return FolderTrashEngine.protection(for: url, home: home)
    }

    /// Builds the review from ticked rooms, capturing each folder's identity now; rooms Room cannot verify drop out.
    func review(_ rooms: [(url: URL, name: String, bytes: Int64)]) -> Review? {
        var requests: [FolderTrashRequest] = []
        var names: [String] = []
        for room in rooms where protection(for: room.url) == nil {
            guard let identity = FolderTrashEngine.identity(of: room.url) else { continue }
            requests.append(FolderTrashRequest(url: room.url, bytes: room.bytes, device: identity.device, inode: identity.inode))
            names.append(room.name)
        }
        return requests.isEmpty ? nil : Review(requests: requests, names: names)
    }

    func move(_ review: Review) async -> FolderTrashReceipt? {
        guard Self.isAvailable, !isMoving else { return nil }
        isMoving = true
        defer { isMoving = false }
        let receipt = await engine.move(review.requests)
        receipts.insert(receipt, at: 0)
        if receipt.failedCount > 0 {
            message = receipt.failedCount == 1 ? "1 folder could not move. It is where it was."
                                               : "\(receipt.failedCount) folders could not move. They are where they were."
        } else {
            message = nil
        }
        if receipt.canRestore { lastMovedID = receipt.id }
        return receipt
    }

    func restore(_ id: UUID) async {
        guard let updated = await engine.restore(receiptID: id) else { return }
        if let index = receipts.firstIndex(where: { $0.id == id }) { receipts[index] = updated }
    }

    /// History shows folder receipts beside cache receipts.
    var activity: [RoomActivity] {
        receipts.map { receipt in
            RoomActivity(id: receipt.id, date: receipt.date, bytes: receipt.items.reduce(0) { $0 + $1.bytes },
                         itemCount: receipt.items.count, restoredCount: receipt.restoredCount, errorCount: receipt.failedCount,
                         canRestore: receipt.canRestore,
                         title: receipt.items.count == 1 ? "1 folder from Disk Map" : "\(receipt.items.count) folders from Disk Map",
                         details: receipt.items.map { item in
                             RoomActivityItem(id: UUID(), name: (item.originalPath as NSString).lastPathComponent,
                                              path: item.originalPath, message: item.message ?? "", isRestored: item.status == .restored,
                                              canRestore: item.status == .trashed, bytes: item.bytes, source: "diskMap")
                         })
        }
    }

    func owns(_ id: UUID) -> Bool { receipts.contains { $0.id == id } }
}
