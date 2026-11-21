// Compiled reference (DISK-MAP-SPEC.md §3.2–§3.4). Proposed path: Sources/RoomCore/RoomTreeBuilder.swift.
// Reuses RoomTreeNode and RoomTreeRetention from design/spec/snippets/RoomLayout.swift unchanged.
//
// RoomTreeRetention.prune needs the whole raw tree in memory first: a home walk is about 1.5 million entries.
// RoomTreeBuilder is the same retention, applied while DiskMapWalker walks: each open directory keeps at most
// 2 × its limit candidate children, so memory is bounded by the kept tree plus the open-directory stack.
// Check DMC-10 proves it gives the same kept structure, bytes and partial flags as prune on random raw trees.
import Foundation

nonisolated struct RoomTreeTotals: Equatable, Sendable {
    var bytes: Int64 = 0
    var files = 0
    var kinds: [String: Int64] = [:]
    var partial = false

    mutating func add(_ other: RoomTreeTotals) {
        bytes += other.bytes
        files += other.files
        for (kind, value) in other.kinds { kinds[kind, default: 0] += value }
        partial = partial || other.partial
    }
}

nonisolated struct RoomTreeBuilder: Sendable {
    private struct Frame: Sendable {
        var name: String
        var relativePath: String
        var depth: Int
        var totals = RoomTreeTotals()
        var kept: [RoomTreeNode] = []
        var other: RoomTreeNode.OtherGroup?
        var limit: Int { RoomTreeRetention.keepPerDepth[depth + 1] ?? 12 }
    }

    private var stack: [Frame]

    init(rootName: String) {
        stack = [Frame(name: rootName, relativePath: "", depth: 0)]
    }

    /// Depth of the directory currently open (root = 0).
    var depth: Int { stack.count - 1 }

    mutating func enterDirectory(_ name: String) {
        let parent = stack[stack.count - 1]
        stack.append(Frame(name: name, relativePath: Self.join(parent.relativePath, name), depth: parent.depth + 1))
    }

    /// One regular file (its attributed bytes: a repeated hardlink passes 0). Returns the node when it is a
    /// top-level child, so the walker can report it in `DiskScanProgress.completedTopLevel`.
    @discardableResult
    mutating func file(_ name: String, bytes: Int64, kind: String?, partial: Bool = false) -> RoomTreeNode? {
        var totals = RoomTreeTotals(bytes: max(0, bytes), files: 1, kinds: [:], partial: partial)
        if let kind, bytes > 0 { totals.kinds[kind] = bytes }
        let parent = stack[stack.count - 1]
        let node = parent.depth <= RoomTreeRetention.maxDepth
            ? RoomTreeNode(name: name, relativePath: Self.join(parent.relativePath, name), allocatedBytes: totals.bytes,
                           fileCount: 1, kindBytes: totals.kinds, isPartial: partial, isDirectory: false,
                           children: [], other: nil)
            : nil
        attach(node, totals: totals)
        return stack.count == 1 ? node : nil
    }

    /// An unreadable entry keeps its place and partial state without counting an unmeasured file.
    mutating func skip(_ name: String, isDirectory: Bool) {
        let parent = stack[stack.count - 1]
        let node = parent.depth < RoomTreeRetention.maxDepth
            ? RoomTreeNode(name: name, relativePath: Self.join(parent.relativePath, name),
                           allocatedBytes: 0, fileCount: 0, kindBytes: [:], isPartial: true,
                           isDirectory: isDirectory, children: [], other: nil)
            : nil
        attach(node, totals: RoomTreeTotals(partial: true))
    }

    /// Closes the open directory. `partial` is this directory's own state (unreadable, changed during the scan).
    @discardableResult
    mutating func leaveDirectory(partial: Bool = false) -> RoomTreeNode? {
        precondition(stack.count > 1, "leaveDirectory without enterDirectory")
        var frame = stack.removeLast()
        frame.totals.partial = frame.totals.partial || partial
        let node = frame.depth <= RoomTreeRetention.maxDepth ? Self.close(frame) : nil
        attach(node, totals: frame.totals)
        return stack.count == 1 ? node : nil
    }

    /// The pruned root. Any directory still open (a cancelled walk) is closed as partial first.
    mutating func finish(partial: Bool = false) -> RoomTreeNode {
        while stack.count > 1 { leaveDirectory(partial: true) }
        var root = stack[0]
        root.totals.partial = root.totals.partial || partial
        return Self.close(root)
    }

    private mutating func attach(_ node: RoomTreeNode?, totals: RoomTreeTotals) {
        var parent = stack.removeLast()
        parent.totals.add(totals)
        if parent.depth < RoomTreeRetention.maxDepth, let node {
            parent.kept.append(node)
            if parent.kept.count > 2 * parent.limit {           // bounded: anything past `limit` here can never be kept
                parent.kept.sort(by: Self.largestFirst)
                for dropped in parent.kept[parent.limit...] { parent.other = Self.fold(parent.other, dropped) }
                parent.kept.removeSubrange(parent.limit...)
            }
        } else if parent.depth == RoomTreeRetention.maxDepth {
            parent.other = Self.fold(parent.other, count: 1, bytes: totals.bytes, partial: totals.partial)
        }
        stack.append(parent)
    }

    private static func close(_ frame: Frame) -> RoomTreeNode {
        var other = frame.other
        var children: [RoomTreeNode] = []
        let sorted = frame.kept.sorted(by: largestFirst)
        for (index, child) in sorted.enumerated() {
            let share = frame.totals.bytes > 0 ? Double(child.allocatedBytes) / Double(frame.totals.bytes) : 0
            if index < frame.limit && (index < RoomTreeRetention.minimumKept || share >= RoomTreeRetention.minimumShare) {
                children.append(child)
            } else {
                other = fold(other, child)
            }
        }
        return RoomTreeNode(name: frame.name, relativePath: frame.relativePath, allocatedBytes: frame.totals.bytes,
                            fileCount: frame.totals.files, kindBytes: frame.totals.kinds, isPartial: frame.totals.partial,
                            isDirectory: true, children: children, other: other)
    }

    /// `itemCount` counts the entries folded at that level (files and folders), not their descendants.
    /// This is what "Other · 1,204 small items" says; RoomTreeRetention.prune's count differs (DISK-MAP-SPEC D-DMB-3).
    private static func fold(_ other: RoomTreeNode.OtherGroup?, _ node: RoomTreeNode) -> RoomTreeNode.OtherGroup {
        fold(other, count: 1, bytes: node.allocatedBytes, partial: node.isPartial)
    }

    private static func fold(_ other: RoomTreeNode.OtherGroup?, count: Int, bytes: Int64, partial: Bool) -> RoomTreeNode.OtherGroup {
        var group = other ?? RoomTreeNode.OtherGroup(itemCount: 0, allocatedBytes: 0, isPartial: false)
        group.itemCount += count
        group.allocatedBytes += bytes
        group.isPartial = group.isPartial || partial
        return group
    }

    /// Same order as RoomTreeRetention.prune: bytes descending, then name ascending.
    static func largestFirst(_ a: RoomTreeNode, _ b: RoomTreeNode) -> Bool {
        a.allocatedBytes != b.allocatedBytes ? a.allocatedBytes > b.allocatedBytes : a.name < b.name
    }

    static func join(_ parent: String, _ name: String) -> String { parent.isEmpty ? name : parent + "/" + name }
}

// MARK: - Node budget (persisted size)

/// Depth retention alone allows 40 + 960 + 15,360 + 184,320 nodes. The budget keeps the largest nodes overall.
/// Because a folder's bytes are the sum of its children, ranking by (bytes desc, depth asc) never keeps a child
/// without its parent. Folded nodes go to their parent's Other, so keptBytes == allocatedBytes still holds.
public nonisolated enum RoomTreeBudget {
    public static let maxNodes = 2_000

    public static func count(_ node: RoomTreeNode) -> Int { node.children.reduce(1) { $0 + count($1) } }

    public static func trim(_ root: RoomTreeNode, maxNodes: Int = maxNodes) -> RoomTreeNode {
        guard count(root) > maxNodes, maxNodes >= 1 else { return root }
        var ranked: [(path: String, bytes: Int64, depth: Int)] = []
        func collect(_ node: RoomTreeNode, depth: Int) {
            for child in node.children {
                ranked.append((child.relativePath, child.allocatedBytes, depth + 1))
                collect(child, depth: depth + 1)
            }
        }
        collect(root, depth: 0)
        ranked.sort { a, b in
            if a.bytes != b.bytes { return a.bytes > b.bytes }
            if a.depth != b.depth { return a.depth < b.depth }
            return a.path < b.path
        }
        let keep = Set(ranked.prefix(maxNodes - 1).map(\.path))
        func rebuild(_ node: RoomTreeNode) -> RoomTreeNode {
            var copy = node
            copy.children = []
            for child in node.children {
                if keep.contains(child.relativePath) { copy.children.append(rebuild(child)) }
                else {
                    var group = copy.other ?? RoomTreeNode.OtherGroup(itemCount: 0, allocatedBytes: 0, isPartial: false)
                    group.itemCount += 1
                    group.allocatedBytes += child.allocatedBytes
                    group.isPartial = group.isPartial || child.isPartial
                    copy.other = group
                }
            }
            return copy
        }
        return rebuild(root)
    }
}

// MARK: - Local navigation (DM-1: stepping in and out never rescans)

nonisolated extension RoomTreeNode {
    public var canStepInside: Bool { !children.isEmpty }

    /// "" is the root. Components are file names, so "/" cannot appear inside one.
    public func descendant(at relativePath: String) -> RoomTreeNode? {
        guard !relativePath.isEmpty else { return self }
        var node = self
        for component in relativePath.split(separator: "/", omittingEmptySubsequences: false) {
            guard let next = node.children.first(where: { $0.name == component }) else { return nil }
            node = next
        }
        return node
    }

    /// Breadcrumb trail from the root to `relativePath`, root first. nil when the path is not kept.
    public func trail(to relativePath: String) -> [RoomTreeNode]? {
        guard !relativePath.isEmpty else { return [self] }
        var out = [self]
        var node = self
        for component in relativePath.split(separator: "/", omittingEmptySubsequences: false) {
            guard let next = node.children.first(where: { $0.name == component }) else { return nil }
            out.append(next)
            node = next
        }
        return out
    }
}

// MARK: - Rescan this folder (DM-3): splice a fresh subtree, ancestors by delta

public nonisolated enum RoomTreeSplice {
    /// Replaces the node at `relativePath` with `fresh` (scanned with that folder as its own root, so its paths are
    /// rebased). Ancestors change by the byte, file and kind delta and are re-sorted. A splice never clears "partial"
    /// on an ancestor: only a rescan of the whole root can show that every other part was read.
    public static func replace(in root: RoomTreeNode, at relativePath: String, with fresh: RoomTreeNode) -> RoomTreeNode? {
        guard !relativePath.isEmpty, let old = root.descendant(at: relativePath) else { return nil }
        let rebased = rebase(fresh, name: old.name, path: relativePath)
        var kindDelta: [String: Int64] = [:]
        for (k, v) in rebased.kindBytes { kindDelta[k, default: 0] += v }
        for (k, v) in old.kindBytes { kindDelta[k, default: 0] -= v }
        let byteDelta = rebased.allocatedBytes - old.allocatedBytes
        let fileDelta = rebased.fileCount - old.fileCount
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        func apply(_ node: RoomTreeNode, _ index: Int) -> RoomTreeNode {
            if index == components.count { return rebased }
            var copy = node
            copy.allocatedBytes += byteDelta
            copy.fileCount += fileDelta
            for (k, v) in kindDelta {
                let value = (copy.kindBytes[k] ?? 0) + v
                copy.kindBytes[k] = value > 0 ? value : nil
            }
            copy.isPartial = copy.isPartial || rebased.isPartial
            copy.children = node.children.map { $0.name == components[index] ? apply($0, index + 1) : $0 }
                .sorted(by: RoomTreeBuilder.largestFirst)
            return copy
        }
        return apply(root, 0)
    }

    static func rebase(_ node: RoomTreeNode, name: String, path: String) -> RoomTreeNode {
        var copy = node
        copy.name = name
        copy.relativePath = path
        copy.children = node.children.map { rebase($0, name: $0.name, path: RoomTreeBuilder.join(path, $0.name)) }
        return copy
    }
}

// MARK: - Largest 20 (06 §10): leaves at the kept depth, Other groups as "Other in X"

public nonisolated enum RoomLargest {
    public struct Row: Equatable, Sendable {
        public var id: String
        public var name: String
        public var bytes: Int64
        public var kind: String?
        public var isPartial: Bool
        public var isOther: Bool
        public var isFolder: Bool
    }

    /// Rows largest first, and the number of items the tree knows under `node` (kept leaves + folded entries).
    public static func rows(in node: RoomTreeNode, limit: Int = 20) -> (rows: [Row], itemCount: Int) {
        var rows: [Row] = []
        var items = 0
        func walk(_ n: RoomTreeNode) {
            if let other = n.other, other.allocatedBytes > 0 {
                rows.append(Row(id: n.relativePath + "\u{0}other", name: "Other in \(n.name)", bytes: other.allocatedBytes,
                                kind: nil, isPartial: other.isPartial, isOther: true, isFolder: false))
            }
            items += n.other?.itemCount ?? 0
            for child in n.children {
                if child.children.isEmpty {
                    items += 1
                    rows.append(Row(id: child.relativePath, name: child.name, bytes: child.allocatedBytes,
                                    kind: StorageKind.dominant(child.kindBytes)?.rawValue, isPartial: child.isPartial,
                                    isOther: false, isFolder: child.isDirectory))
                } else { walk(child) }
            }
        }
        walk(node)
        rows.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
        return (Array(rows.prefix(limit)), items)
    }
}
