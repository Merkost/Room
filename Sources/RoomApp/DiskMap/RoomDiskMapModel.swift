import Foundation
import Observation
import RoomCore

nonisolated struct RoomMapCleanupTarget: Equatable {
    let url: URL
    let revision: UUID
    let levelPath: String
    let selectedPath: String?

    var path: String { selectedPath ?? levelPath }
    var includesContents: Bool { !path.isEmpty }
}

/// Navigation reads the bounded result of the last walk. Only explicit map actions call the engine.
@Observable @MainActor
final class RoomDiskMapModel {
    private var revision = UUID()
    private(set) var current: RoomStoredTree?
    private(set) var rootURL: URL?
    private(set) var changedAt: Date?
    private(set) var pendingFolder: URL?

    var hasLostAccess: Bool { current != nil && rootURL == nil }
    private(set) var levelPath = ""
    private(set) var selectedPath: String?
    private(set) var progress: DiskScanProgress?
    private(set) var blueprint: RoomBlueprint?
    private(set) var catalog = RoomTreeCatalog()

    var level: RoomTreeNode? { current?.tree.descendant(at: levelPath) }
    var trail: [RoomTreeNode] { current?.tree.trail(to: levelPath) ?? [] }
    var canStepOut: Bool { !levelPath.isEmpty }
    var canCompare: Bool { comparison != nil }
    var cleanupTarget: RoomMapCleanupTarget? {
        let path = selectedPath ?? levelPath
        guard let current, !current.cancelled, current.tree.descendant(at: path) != nil,
              let url = url(for: path) else { return nil }
        return RoomMapCleanupTarget(url: url, revision: revision, levelPath: levelPath, selectedPath: selectedPath)
    }
    var comparison: (earlier: RoomTreeNode, date: Date)? {
        guard let current, !current.cancelled, let previous = catalog.entries[current.rootID]?.previous,
              RoomCompare.isAvailable(current: current, previous: previous),
              let earlier = previous.tree.descendant(at: levelPath) else { return nil }
        return (earlier, previous.scannedAt)
    }

    func begin(url: URL) {
        revision = UUID()
        if rootURL?.standardizedFileURL != url.standardizedFileURL {
            current = nil
            levelPath = ""
            selectedPath = nil
        }
        rootURL = url
        pendingFolder = nil
        progress = nil
        let earlier = Dictionary(uniqueKeysWithValues: (current?.tree.children ?? []).map { node in
            (node.name, (node.allocatedBytes, StorageKind.dominant(node.kindBytes)?.rawValue))
        })
        blueprint = RoomBlueprint(earlier: earlier, earlierDate: current?.scannedAt)
    }

    func accept(_ update: DiskScanProgress) {
        progress = update
        let now = Date()
        if let total = update.topLevelTotal { blueprint?.setTopLevelTotal(total) }
        blueprint?.progress(files: update.visitedFiles, bytes: update.allocatedBytes)
        for room in update.completedTopLevel {
            blueprint?.completed(name: room.name, bytes: room.bytes,
                kind: StorageKind.dominant(room.kindBytes)?.rawValue, isPartial: room.isPartial, at: now)
        }
        blueprint?.tick(now)
    }

    func record(_ mapped: DiskTreeReport, rootID: String, displayPath: String, isHome: Bool) {
        let map = RoomStoredTree(rootID: rootID, displayPath: displayPath, scannedAt: mapped.report.scannedAt,
            cancelled: mapped.report.cancelled, volumeUUID: mapped.volumeID,
            issueCount: mapped.report.unreadableItemCount, tree: RoomTreeBudget.trim(mapped.tree))
        if map.cancelled { blueprint?.stop(at: map.scannedAt) }
        else { blueprint?.finish(at: map.scannedAt) }
        install(map, url: mapped.report.url, isHome: isHome)
    }

    func install(_ map: RoomStoredTree, url: URL, isHome: Bool = false) {
        revision = UUID()
        if rootURL?.standardizedFileURL != url.standardizedFileURL { levelPath = "" }
        rootURL = url
        pendingFolder = nil
        current = map
        if map.tree.descendant(at: levelPath)?.isDirectory != true { levelPath = "" }
        selectedPath = nil
        if isHome { catalog.homeRootID = map.rootID }
        catalog.record(map, now: map.scannedAt)
    }

    func restore(_ map: RoomStoredTree, previous: RoomStoredTree?, root: RoomTreeStore.Root, url: URL?) {
        revision = UUID()
        rootURL = url
        pendingFolder = nil
        current = map
        changedAt = root.changedAt
        levelPath = ""
        selectedPath = nil
        catalog.restore(current: map, previous: previous, lastUsed: root.lastUsed)
    }

    func updateChangeDate(_ updated: Date?) { changedAt = updated }

    func showUnmapped(_ url: URL) {
        removeCurrent()
        pendingFolder = url
    }

    /// Root-level selection uses an approved URL supplied by the caller and never reads a new folder.
    @discardableResult
    func openRetained(_ url: URL) -> Bool {
        guard let rootURL, RoomFileAccess.contains(parent: rootURL, child: url) else { return false }
        let parts = url.standardizedFileURL.pathComponents.dropFirst(rootURL.standardizedFileURL.pathComponents.count)
        return go(to: parts.joined(separator: "/"))
    }

    func select(_ path: String?) { selectedPath = path }

    @discardableResult
    func go(to relativePath: String) -> Bool {
        guard let node = current?.tree.descendant(at: relativePath), node.isDirectory,
              relativePath.isEmpty || node.canStepInside else { return false }
        levelPath = relativePath
        selectedPath = nil
        return true
    }

    func stepOut() {
        guard canStepOut else { return }
        go(to: levelPath.split(separator: "/").dropLast().joined(separator: "/"))
    }

    func removeCurrent() {
        if let current { catalog.forget(current.rootID) }
        current = nil
        rootURL = nil
        levelPath = ""
        selectedPath = nil
        progress = nil
        blueprint = nil
        changedAt = nil
        pendingFolder = nil
    }

    func url(for relativePath: String) -> URL? {
        guard let rootURL else { return nil }
        return relativePath.isEmpty ? rootURL : rootURL.appendingPathComponent(relativePath)
    }

    func replaceSubtree(at path: String, with result: DiskTreeReport) {
        guard !result.report.cancelled, var current,
              let updated = RoomTreeSplice.replace(in: current.tree, at: path, with: result.tree) else { return }
        current.tree = RoomTreeBudget.trim(updated)
        revision = UUID()
        self.current = current
        if current.tree.descendant(at: levelPath)?.isDirectory != true { levelPath = "" }
    }
}
