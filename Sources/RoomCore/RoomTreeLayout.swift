import Foundation

public nonisolated struct RoomTreeNode: Sendable, Codable, Equatable {
    public var name: String
    public var relativePath: String           // relative to the scan root; never absolute in persisted form
    public var allocatedBytes: Int64
    public var fileCount: Int
    public var kindBytes: [String: Int64]     // RoomTokens.Kind raw value -> bytes
    public var isPartial: Bool
    public var isDirectory: Bool
    /// Children kept: top N by size. The rest are folded into `other`.
    public var children: [RoomTreeNode]
    public var other: OtherGroup?

    public init(name: String, relativePath: String, allocatedBytes: Int64, fileCount: Int,
                kindBytes: [String: Int64], isPartial: Bool, isDirectory: Bool,
                children: [RoomTreeNode], other: OtherGroup?) {
        self.name = name
        self.relativePath = relativePath
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.kindBytes = kindBytes
        self.isPartial = isPartial
        self.isDirectory = isDirectory
        self.children = children
        self.other = other
    }

    public struct OtherGroup: Sendable, Codable, Equatable {
        public var itemCount: Int
        public var allocatedBytes: Int64
        public var isPartial: Bool

        public init(itemCount: Int, allocatedBytes: Int64, isPartial: Bool) {
            self.itemCount = itemCount
            self.allocatedBytes = allocatedBytes
            self.isPartial = isPartial
        }
    }
}

public nonisolated enum RoomTreeRetention {
    /// Keep per level: 40 at depth 1, 24 at depth 2, 16 at depth 3, 12 at depth 4; nothing below depth 4.
    public static let keepPerDepth = [1: 40, 2: 24, 3: 16, 4: 12]
    public static let maxDepth = 4
    /// Also fold children smaller than 0.2 % of their parent (but always keep at least 8 if present).
    public static let minimumShare = 0.002
    public static let minimumKept = 8

    public static func prune(_ node: RoomTreeNode, depth: Int = 0) -> RoomTreeNode {
        var copy = node
        guard depth < maxDepth else {
            let folded = node.children.reduce(into: RoomTreeNode.OtherGroup(itemCount: 0, allocatedBytes: 0, isPartial: false)) {
                $0.itemCount += 1; $0.allocatedBytes += $1.allocatedBytes; $0.isPartial = $0.isPartial || $1.isPartial
            }
            copy.children = []
            copy.other = mergeOther(node.other, folded.itemCount > 0 ? folded : nil)
            return copy
        }
        let limit = keepPerDepth[depth + 1] ?? 12
        let sorted = node.children.sorted { $0.allocatedBytes != $1.allocatedBytes ? $0.allocatedBytes > $1.allocatedBytes : $0.name < $1.name }
        var kept: [RoomTreeNode] = [], dropped: [RoomTreeNode] = []
        for (i, child) in sorted.enumerated() {
            let share = node.allocatedBytes > 0 ? Double(child.allocatedBytes) / Double(node.allocatedBytes) : 0
            if i < limit && (i < minimumKept || share >= minimumShare) { kept.append(child) } else { dropped.append(child) }
        }
        copy.children = kept.map { prune($0, depth: depth + 1) }
        let folded = dropped.reduce(into: RoomTreeNode.OtherGroup(itemCount: 0, allocatedBytes: 0, isPartial: false)) {
            $0.itemCount += 1 + ($1.other?.itemCount ?? 0) + countDescendants($1)
            $0.allocatedBytes += $1.allocatedBytes; $0.isPartial = $0.isPartial || $1.isPartial
        }
        copy.other = mergeOther(node.other, folded.itemCount > 0 ? folded : nil)
        return copy
    }

    private static func countDescendants(_ n: RoomTreeNode) -> Int { n.children.reduce(0) { $0 + 1 + countDescendants($1) } }
    private static func mergeOther(_ a: RoomTreeNode.OtherGroup?, _ b: RoomTreeNode.OtherGroup?) -> RoomTreeNode.OtherGroup? {
        switch (a, b) {
        case (nil, nil): nil
        case (let x?, nil): x
        case (nil, let y?): y
        case (let x?, let y?): .init(itemCount: x.itemCount + y.itemCount, allocatedBytes: x.allocatedBytes + y.allocatedBytes, isPartial: x.isPartial || y.isPartial)
        }
    }

    /// Invariant checked by tests: a node's bytes equal its kept children + other (within the node's own files).
    public static func keptBytes(_ n: RoomTreeNode) -> Int64 { n.children.reduce(n.other?.allocatedBytes ?? 0) { $0 + $1.allocatedBytes } }
}
