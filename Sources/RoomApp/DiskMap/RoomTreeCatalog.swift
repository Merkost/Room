import RoomCore
// Compiled reference (DISK-MAP-SPEC.md §3.5, §8). Proposed paths: Sources/RoomCore/RoomTreeCatalog.swift
// (pure retention rules used by the RoomTreeStore actor) and Sources/RoomApp/RoomHomeMap.swift (Overview adapter).
import CryptoKit
import Foundation

/// One persisted map of one root. Paths inside `tree` are relative; the absolute root is resolved from
/// RoomFileAccess (Store) or the standardized path (Direct) and is never written next to the tree in Store.
nonisolated struct RoomStoredTree: Codable, Equatable, Sendable {
    var rootID: String
    var displayPath: String          // "~/Projects" style, for subtitles; never used to open files
    var scannedAt: Date
    var cancelled: Bool
    var volumeUUID: String?          // URLResourceValues.volumeUUIDString of the root at scan time
    var issueCount: Int
    var tree: RoomTreeNode
    var isPartial: Bool { cancelled || tree.isPartial }

    /// The saved map already bounds the retained nodes. This projection never opens the folders or files.
    func metadataReport(for root: URL) -> DiskMapReport {
        func item(_ node: RoomTreeNode) -> DiskMapItem? {
            let path = RoomTreeLocation(approvalID: rootID, relativePath: node.relativePath)
            guard !node.relativePath.isEmpty, let resolved = path.resolve(under: root) else { return nil }
            let url = URL(fileURLWithPath: resolved.path, isDirectory: node.isDirectory)
            return DiskMapItem(url: url, name: node.name, isDirectory: node.isDirectory, allocatedBytes: node.allocatedBytes,
                logicalBytes: 0, fileCount: node.fileCount)
        }

        var pending = tree.children
        var files: [DiskMapItem] = []
        while let node = pending.popLast() {
            if node.isDirectory { pending.append(contentsOf: node.children) }
            else if let file = item(node) { files.append(file) }
        }
        let largest = files.sorted {
            $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes
        }.prefix(100)
        return DiskMapReport(id: UUID(), url: root, scannedAt: scannedAt,
            children: tree.children.compactMap(item), largestFiles: Array(largest),
            allocatedBytes: tree.allocatedBytes, logicalBytes: 0, fileCount: tree.fileCount,
            issues: [], cancelled: cancelled, isPartial: isPartial, unreadableItemCount: issueCount)
    }
}

nonisolated enum RoomTreeRootID {
    /// Direct: SHA-256 of the standardized path (04 §3.6), first 16 bytes hex. Store: the RoomFileAccess record id.
    static func direct(standardizedPath: String) -> String {
        SHA256.hash(data: Data(standardizedPath.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// DM-5 and 04 §2: per root, the current tree and one previous tree at least 3 days older; 8 roots, LRU,
/// the home root never evicted (the Overview reads it).
nonisolated struct RoomTreeCatalog: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var current: RoomStoredTree
        var previous: RoomStoredTree?
        var lastUsed: Date
    }

    static let maxRoots = 8
    static let previousMinimumAge: TimeInterval = 3 * 86_400

    private(set) var entries: [String: Entry] = [:]
    var homeRootID: String?

    /// Records a finished walk. A stopped walk never replaces a complete map (it stays in memory for the session,
    /// drawn with "≥"); it is persisted only when the root has no map yet. Returns false when nothing was stored.
    @discardableResult
    mutating func record(_ tree: RoomStoredTree, now: Date) -> Bool {
        guard let existing = entries[tree.rootID] else {
            entries[tree.rootID] = Entry(current: tree, previous: nil, lastUsed: now)
            evict()
            return true
        }
        if tree.cancelled && !existing.current.cancelled { return false }
        guard tree.scannedAt > existing.current.scannedAt else { return false }
        // Keep the newest earlier map that is at least 3 days older than the new one.
        let candidates = [existing.current, existing.previous].compactMap { $0 }
            .filter { !$0.cancelled && tree.scannedAt.timeIntervalSince($0.scannedAt) >= Self.previousMinimumAge }
        let previous = candidates.max { $0.scannedAt < $1.scannedAt }
        entries[tree.rootID] = Entry(current: tree, previous: previous, lastUsed: now)
        evict()
        return true
    }

    mutating func restore(current: RoomStoredTree, previous: RoomStoredTree?, lastUsed: Date) {
        entries[current.rootID] = Entry(current: current, previous: previous, lastUsed: lastUsed)
        evict()
    }

    mutating func touch(_ rootID: String, now: Date) { entries[rootID]?.lastUsed = now }
    mutating func forget(_ rootID: String) { entries[rootID] = nil }

    private mutating func evict() {
        while entries.count > Self.maxRoots {
            guard let victim = entries.filter({ $0.key != homeRootID })
                .min(by: { $0.value.lastUsed != $1.value.lastUsed ? $0.value.lastUsed < $1.value.lastUsed : $0.key < $1.key })
            else { return }
            entries[victim.key] = nil
        }
    }
}

// MARK: - What the Overview may draw from maps (05 §1 kinds, §4.1; 19 D-7)

nonisolated struct RoomHomeKinds: Equatable, Sendable {
    var kinds: [(String, Double)]    // StorageKind raw value, decimal GB; only kinds with bytes > 0
    var mappedBytes: Int64
    var notMappedBytes: Int64
    var mappedAt: Date               // the oldest contributing scan: the caption dates the plan by it
    static func == (a: Self, b: Self) -> Bool {
        a.mappedBytes == b.mappedBytes && a.notMappedBytes == b.notMappedBytes && a.mappedAt == b.mappedAt &&
            a.kinds.map(\.0) == b.kinds.map(\.0) && a.kinds.map(\.1) == b.kinds.map(\.1)
    }
}

nonisolated enum RoomHomeMap {
    enum Refusal: Error, Equatable, Sendable { case noHomeMap, stoppedMap, otherVolume, unknownVolume, exceedsUsedSpace, overlappingRoots }

    /// `roots` are maps the Overview may sum: the account home and, in Direct, /Applications. They must not nest.
    /// Kinds are what those walks measured; everything else in capacity − free stays Not mapped yet (no dots).
    static func kinds(roots: [(path: String, map: RoomStoredTree)], capacityBytes: Int64, freeBytes: Int64,
                      capacityVolumeUUID: String?) -> Result<RoomHomeKinds, Refusal> {
        guard !roots.isEmpty else { return .failure(.noHomeMap) }
        guard let volume = capacityVolumeUUID else { return .failure(.unknownVolume) }
        for (i, a) in roots.enumerated() {
            for b in roots[(i + 1)...] where nests(a.path, b.path) || nests(b.path, a.path) {
                return .failure(.overlappingRoots)
            }
            if a.map.cancelled { return .failure(.stoppedMap) }
            guard let v = a.map.volumeUUID else { return .failure(.unknownVolume) }
            if v != volume { return .failure(.otherVolume) }
        }
        var sums: [String: Int64] = [:]
        for root in roots { for (k, v) in root.map.tree.kindBytes where v > 0 { sums[k, default: 0] += v } }
        let mapped = sums.values.reduce(0, +)
        let used = capacityBytes - freeBytes
        // APFS clones and stale maps can make allocated sums exceed what the volume uses. Then the walls
        // cannot fit the house; draw no kinds rather than shrink or rescale measured numbers.
        guard mapped <= used else { return .failure(.exceedsUsedSpace) }
        let ordered = StorageKind.allCases.compactMap { kind -> (String, Double)? in
            guard let v = sums[kind.rawValue], v > 0 else { return nil }
            return (kind.rawValue, Double(v) / 1e9)
        }
        return .success(RoomHomeKinds(kinds: ordered, mappedBytes: mapped, notMappedBytes: used - mapped,
                                      mappedAt: roots.map(\.map.scannedAt).min()!))
    }

    static func nests(_ parent: String, _ child: String) -> Bool {
        child == parent || child.hasPrefix(parent == "/" ? "/" : parent + "/")
    }
}
