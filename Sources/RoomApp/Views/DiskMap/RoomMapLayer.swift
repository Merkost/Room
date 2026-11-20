import RoomCore
// Compiled reference (DISK-MAP-SPEC.md §5). Proposed path: Sources/RoomApp/Views/DiskMap/RoomMapLayer.swift
// (the pure half; RoomMapCanvas draws it). Reuses RoomSquarify from design/spec/snippets/RoomLayout.swift.
// Values are board v4 `45-screens.js` buildLayer/tileHTML: 1.5 pt inset per tile (3 pt between tiles), groups
// ≥ 120 × 80 with children in (x+3, y+22, w−6, h−25), labels name+size ≥ 74 × 40, name ≥ 44 × 22.
import CoreGraphics
import Foundation

nonisolated enum RoomMapLabel: Sendable, Equatable { case nameAndSize, nameOnly, none }
nonisolated enum RoomMapDirection: Sendable { case left, right, up, down }

nonisolated struct RoomMapItem: Sendable, Equatable {
    enum Role: Sendable, Equatable { case tile, group }
    var id: String               // tree relativePath; Other = parent path + "\u{0}other"
    var name: String
    var bytes: Int64
    var kind: String?            // StorageKind raw (dominant); nil = Other (Surface.track)
    var isPartial: Bool
    var isOther: Bool
    var otherCount: Int
    var canStepInside: Bool
    var role: Role
    var cell: CGRect             // squarified cell, used for label thresholds and hit testing
    var drawRect: CGRect         // cell inset by `gap`
    var headerRect: CGRect?      // groups: the step-inside hit region
    var label: RoomMapLabel
    var parentID: String         // the level node's path, or the group's id for inner tiles
}

nonisolated struct RoomMapLayer: Sendable {
    static let gap: CGFloat = 1.5
    static let groupMinimum = CGSize(width: 120, height: 80)
    static let groupTop: CGFloat = 22
    static let groupInset: CGFloat = 3
    static let maxTiles = 600
    static let minimumSide: CGFloat = 2
    static let nameAndSize = CGSize(width: 74, height: 40)
    static let nameOnly = CGSize(width: 44, height: 22)

    var items: [RoomMapItem]

    static func otherID(_ path: String) -> String { path + "\u{0}other" }

    static func make(level: RoomTreeNode, size: CGSize) -> RoomMapLayer {
        let bounds = CGRect(origin: .zero, size: size)
        var top = layout(level, in: bounds)
        var inner: [String: [RoomMapItem]] = [:]
        // Groups first pass: which top cells become groups, and how many inner tiles each would draw.
        var groupNodes: [String: RoomTreeNode] = [:]
        for item in top where item.canStepInside && item.cell.width >= groupMinimum.width && item.cell.height >= groupMinimum.height {
            if let node = level.children.first(where: { $0.relativePath == item.id }) { groupNodes[item.id] = node }
        }
        // Tile cap: fold the smallest inner child of the busiest group until the whole level is ≤ maxTiles.
        func entries(_ n: RoomTreeNode) -> Int { n.children.count + ((n.other?.allocatedBytes ?? 0) > 0 ? 1 : 0) }
        func total() -> Int { top.count + groupNodes.values.reduce(0) { $0 + entries($1) } }
        while total() > maxTiles {
            guard let key = groupNodes.keys.sorted().max(by: { entries(groupNodes[$0]!) < entries(groupNodes[$1]!) }),
                  var node = groupNodes[key], let smallest = node.children.popLast() else { break }
            var group = node.other ?? .init(itemCount: 0, allocatedBytes: 0, isPartial: false)
            group.itemCount += 1; group.allocatedBytes += smallest.allocatedBytes; group.isPartial = group.isPartial || smallest.isPartial
            node.other = group
            groupNodes[key] = node
        }
        for index in top.indices {
            guard let node = groupNodes[top[index].id] else { continue }
            let c = top[index].cell
            let area = CGRect(x: c.minX + groupInset, y: c.minY + groupTop, width: c.width - 2 * groupInset, height: c.height - groupTop - groupInset)
            top[index].role = .group
            top[index].headerRect = CGRect(x: c.minX + gap, y: c.minY + gap, width: c.width - 2 * gap, height: groupTop - gap)
            top[index].label = .nameAndSize
            inner[top[index].id] = layout(node, in: area).map { var t = $0; t.parentID = top[index].id; return t }
        }
        var all: [RoomMapItem] = []
        for item in top {
            all.append(item)
            all += inner[item.id] ?? []
        }
        return RoomMapLayer(items: all)
    }

    /// Squarify one node's kept children plus Other. Cells thinner than 2 pt fold into Other and the node is laid
    /// out again (at most 3 passes), so no tile is drawn as a hairline and no byte disappears.
    static func layout(_ node: RoomTreeNode, in rect: CGRect) -> [RoomMapItem] {
        var children = node.children.filter { $0.allocatedBytes > 0 }
        var other = node.other
        for _ in 0..<3 {
            var weighted = children.map { RoomWeighted(id: $0.relativePath, bytes: $0.allocatedBytes) }
            if let other, other.allocatedBytes > 0 { weighted.append(RoomWeighted(id: otherID(node.relativePath), bytes: other.allocatedBytes, isOther: true)) }
            let placed = RoomSquarify.layout(weighted, in: rect)
            let thin = Set(placed.filter { min($0.rect.width, $0.rect.height) < minimumSide }.map(\.id))
                .subtracting([otherID(node.relativePath)])
            if thin.isEmpty || children.isEmpty {
                return placed.map { cell in
                    let child = children.first { $0.relativePath == cell.id }
                    return item(child: child, other: other, cell: cell.rect, parent: node.relativePath)
                }
            }
            var group = other ?? .init(itemCount: 0, allocatedBytes: 0, isPartial: false)
            for child in children where thin.contains(child.relativePath) {
                group.itemCount += 1; group.allocatedBytes += child.allocatedBytes; group.isPartial = group.isPartial || child.isPartial
            }
            other = group
            children.removeAll { thin.contains($0.relativePath) }
        }
        return layout(RoomTreeNode(name: node.name, relativePath: node.relativePath, allocatedBytes: node.allocatedBytes,
                                   fileCount: node.fileCount, kindBytes: node.kindBytes, isPartial: node.isPartial,
                                   isDirectory: node.isDirectory, children: [], other: other), in: rect)
    }

    private static func item(child: RoomTreeNode?, other: RoomTreeNode.OtherGroup?, cell: CGRect, parent: String) -> RoomMapItem {
        let label: RoomMapLabel = cell.width >= nameAndSize.width && cell.height >= nameAndSize.height ? .nameAndSize
            : cell.width >= nameOnly.width && cell.height >= nameOnly.height ? .nameOnly : .none
        let draw = cell.insetBy(dx: gap, dy: gap)
        if let child {
            return RoomMapItem(id: child.relativePath, name: child.name, bytes: child.allocatedBytes,
                               kind: StorageKind.dominant(child.kindBytes)?.rawValue, isPartial: child.isPartial,
                               isOther: false, otherCount: 0, canStepInside: child.canStepInside, role: .tile,
                               cell: cell, drawRect: draw, headerRect: nil, label: label, parentID: parent)
        }
        return RoomMapItem(id: otherID(parent), name: "Other", bytes: other?.allocatedBytes ?? 0, kind: nil,
                           isPartial: other?.isPartial ?? false, isOther: true, otherCount: other?.itemCount ?? 0,
                           canStepInside: false, role: .tile, cell: cell, drawRect: draw, headerRect: nil,
                           label: label, parentID: parent)
    }

    // MARK: Hit testing (DM-17): a linear scan, headers first, then tiles, then group bodies.

    struct Hit: Equatable, Sendable { let item: RoomMapItem; let isHeader: Bool }

    func hit(_ p: CGPoint) -> Hit? {
        for item in items where item.role == .group { if item.headerRect?.contains(p) == true { return Hit(item: item, isHeader: true) } }
        for item in items where item.role == .tile { if item.cell.contains(p) { return Hit(item: item, isHeader: false) } }
        for item in items where item.role == .group { if item.cell.contains(p) { return Hit(item: item, isHeader: false) } }
        return nil
    }

    // MARK: Keyboard (06 §12) and VoiceOver order (DM-19)

    /// Tab order and the "Largest items" rotor: every item by size, ties by id.
    var sizeOrder: [String] {
        items.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }.map(\.id)
    }

    private func anchor(_ item: RoomMapItem) -> CGPoint {
        let r = item.headerRect ?? item.cell
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// Nearest item centre-to-centre within 45° of the direction; if none, nearest with any positive component.
    /// Ties by size. A group's anchor is its header, so arrows can reach the folder and its inner tiles.
    func neighbour(of id: String, _ direction: RoomMapDirection) -> String? {
        guard let from = items.first(where: { $0.id == id }) else { return nil }
        let a = anchor(from)
        func components(_ p: CGPoint) -> (primary: CGFloat, secondary: CGFloat) {
            switch direction {
            case .right: (p.x - a.x, abs(p.y - a.y))
            case .left: (a.x - p.x, abs(p.y - a.y))
            case .down: (p.y - a.y, abs(p.x - a.x))
            case .up: (a.y - p.y, abs(p.x - a.x))
            }
        }
        let others = items.filter { $0.id != id }
        func best(_ cone: Bool) -> String? {
            others.compactMap { item -> (RoomMapItem, CGFloat)? in
                let p = anchor(item), c = components(p)
                guard c.primary > 0, !cone || c.secondary <= c.primary else { return nil }
                return (item, hypot(p.x - a.x, p.y - a.y))
            }
            .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.bytes > $1.0.bytes }?.0.id
        }
        return best(true) ?? best(false)
    }
}

// MARK: - Speech (DM-19, 15 §1): "studio-kmp, folder, 21.6 gigabytes, 29 percent of Projects"

nonisolated enum RoomMapSpeech {
    static func label(_ item: RoomMapItem, parentName: String, parentBytes: Int64, spoken: (Int64) -> String,
                      hidden: Bool = false) -> String {
        let what = item.isOther ? "Other, \(item.otherCount) small items" : item.canStepInside || item.role == .group ? "\(item.name), folder" : item.name
        // Hide (PE-24) masks Disk Map names and sizes: nothing of either is spoken.
        guard !hidden else { return item.isOther ? "Other, size hidden" : (item.canStepInside || item.role == .group ? "Folder" : "Item") + ", name and size hidden" }
        let size = (item.isPartial ? "at least " : "") + spoken(item.bytes)
        let percent = parentBytes > 0 ? Int((Double(item.bytes) / Double(parentBytes) * 100).rounded()) : 0
        return "\(what), \(size), \(percent) percent of \(parentName)"
    }
}
