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
        /// Rooms that were ticked but could not be verified, so they are not in this review.
        var dropped: [String] = []
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
    /// Cache cleanups and restores in progress elsewhere: one cleanup at a time across Room.
    @ObservationIgnored var otherCleanupBusy: () -> Bool = { false }
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

    var canMove: Bool { Self.isAvailable && !isMoving && !otherCleanupBusy() }

    func protection(for url: URL?) -> FolderProtection? {
        guard Self.isAvailable else { return .unverified }
        guard let url else { return .unverified }
        return FolderTrashEngine.protection(for: url, home: home)
    }

    /// Builds the review from ticked rooms, capturing each folder's identity now; rooms Room cannot verify drop out.
    func review(_ rooms: [(url: URL, name: String, bytes: Int64)]) -> Review? {
        var requests: [FolderTrashRequest] = []
        var names: [String] = []
        var dropped: [String] = []
        for room in rooms {
            guard protection(for: room.url) == nil, let identity = FolderTrashEngine.identity(of: room.url) else {
                dropped.append(room.name)
                continue
            }
            requests.append(FolderTrashRequest(url: room.url, bytes: room.bytes, device: identity.device, inode: identity.inode))
            names.append(room.name)
        }
        return requests.isEmpty ? nil : Review(requests: requests, names: names, dropped: dropped)
    }

    func move(_ review: Review) async -> FolderTrashReceipt? {
        guard canMove else {
            message = "Room is already moving or restoring something. Try again when it finishes."
            return nil
        }
        isMoving = true
        defer { isMoving = false }
        let receipt: FolderTrashReceipt
        do {
            receipt = try await engine.move(review.requests)
        } catch {
            message = "Room could not save a receipt, so nothing moved."
            return nil
        }
        if receipt.movedCount > 0 { receipts.insert(receipt, at: 0) }
        message = Self.summary(receipt)
        if receipt.canRestore { lastMovedID = receipt.id }
        return receipt
    }

    /// One plain line about what did not go to plan, or nil when every folder moved and the receipt is safe.
    static func summary(_ receipt: FolderTrashReceipt) -> String? {
        var lines: [String] = []
        let failed = receipt.failedCount
        if failed > 0 {
            lines.append(failed == 1 ? "1 folder did not move. It is where it was." : "\(failed) folders did not move. They are where they were.")
        }
        if receipt.receiptWriteFailed {
            lines.append("Room could not finish writing the receipt. Restore works until Room quits.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    /// Restores and says what happened: "Put back", or how many came back and why the rest stayed.
    @discardableResult
    func restore(_ id: UUID) async -> String {
        guard Self.isAvailable, !isMoving, !otherCleanupBusy() else { return "Room is busy. Try again in a moment." }
        isMoving = true
        defer { isMoving = false }
        guard let updated = await engine.restore(receiptID: id) else { return "Room could not read this receipt." }
        if let index = receipts.firstIndex(where: { $0.id == id }) { receipts[index] = updated }
        return Self.restoreOutcome(updated)
    }

    static func restoreOutcome(_ receipt: FolderTrashReceipt) -> String {
        let moved = receipt.items.filter { $0.status == .trashed || $0.status == .restored }
        let back = moved.filter { $0.status == .restored }.count
        if back == moved.count { return "Put back" }
        let reason = moved.first { $0.status == .trashed }?.message ?? "The rest stays in Trash."
        return "\(back) of \(moved.count) put back. \(reason)"
    }

    /// History shows folder receipts beside cache receipts.
    var activity: [RoomActivity] {
        // Only folders that actually moved count; a receipt where nothing moved is not shown as space made.
        receipts.filter { $0.movedCount > 0 }.map { receipt in
            RoomActivity(id: receipt.id, date: receipt.date, bytes: receipt.movedBytes,
                         itemCount: receipt.movedCount, restoredCount: receipt.restoredCount, errorCount: receipt.failedCount,
                         canRestore: receipt.canRestore,
                         title: receipt.movedCount == 1 ? "1 folder from Disk Map" : "\(receipt.movedCount) folders from Disk Map",
                         details: receipt.items.filter { $0.status == .trashed || $0.status == .restored }.map { item in
                             RoomActivityItem(id: UUID(), name: (item.originalPath as NSString).lastPathComponent,
                                              path: item.originalPath, message: item.message ?? "", isRestored: item.status == .restored,
                                              canRestore: item.status == .trashed, bytes: item.bytes, source: "diskMap")
                         })
        }
    }

    func owns(_ id: UUID) -> Bool { receipts.contains { $0.id == id } }
}
