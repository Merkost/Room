// Pure layout logic shared by the Disk Map, the Overview dot plan, onboarding and the website parity check.
// Spec: 05-OVERVIEW.md §4, 06-DISK-MAP.md §3. Lives in RoomCore (nonisolated, Sendable, unit-tested).
import CoreGraphics
import Foundation

/// One weighted input. `isOther` items always sort last ("Other · 1,204 small items").
public nonisolated struct RoomWeighted<ID: Hashable & Sendable>: Sendable {
    public var id: ID
    public var bytes: Int64
    public var isOther: Bool

    public init(id: ID, bytes: Int64, isOther: Bool = false) {
        self.id = id
        self.bytes = bytes
        self.isOther = isOther
    }
}

public nonisolated struct RoomPlacedRect<ID: Hashable & Sendable>: Sendable {
    public var id: ID
    public var rect: CGRect

    public init(id: ID, rect: CGRect) {
        self.id = id
        self.rect = rect
    }
}

/// Squarified treemap (Bruls, Huizing, van Wijk 2000). Deterministic: ties broken by input order.
/// Items with bytes <= 0 are dropped (a missing size is never drawn as a zero-area tile).
public nonisolated enum RoomSquarify {
    /// `pinnedFirst` is laid out first whatever its size (the plan's free room: the pocket stays top-left).
    public static func layout<ID>(_ items: [RoomWeighted<ID>], in bounds: CGRect, pinnedFirst: ID? = nil) -> [RoomPlacedRect<ID>] {
        let sorted = items.enumerated()
            .filter { $0.element.bytes > 0 }
            .sorted { lhs, rhs in
                if let pin = pinnedFirst, (lhs.element.id == pin) != (rhs.element.id == pin) { return lhs.element.id == pin }
                if lhs.element.isOther != rhs.element.isOther { return !lhs.element.isOther }
                if lhs.element.bytes != rhs.element.bytes { return lhs.element.bytes > rhs.element.bytes }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        let total = sorted.reduce(0.0) { $0 + Double($1.bytes) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let scale = Double(bounds.width * bounds.height) / total
        var queue = sorted.map { (item: $0, area: Double($0.bytes) * scale) }[...]
        var free = bounds
        var row: [(item: RoomWeighted<ID>, area: Double)] = []
        var out: [RoomPlacedRect<ID>] = []
        out.reserveCapacity(sorted.count)

        func worst(_ row: [(item: RoomWeighted<ID>, area: Double)], side: Double) -> Double {
            let sum = row.reduce(0) { $0 + $1.area }
            guard sum > 0, side > 0, let maxA = row.map(\.area).max(), let minA = row.map(\.area).min(), minA > 0 else { return .infinity }
            let s2 = side * side, sum2 = sum * sum
            return max(s2 * maxA / sum2, sum2 / (s2 * minA))
        }
        func place(_ row: [(item: RoomWeighted<ID>, area: Double)]) {
            let sum = row.reduce(0) { $0 + $1.area }
            if free.width >= free.height {               // lay a column on the left
                let w = CGFloat(sum) / free.height
                var y = free.minY
                for cell in row {
                    let h = CGFloat(cell.area) / w
                    out.append(RoomPlacedRect(id: cell.item.id, rect: CGRect(x: free.minX, y: y, width: w, height: h)))
                    y += h
                }
                free = CGRect(x: free.minX + w, y: free.minY, width: max(0, free.width - w), height: free.height)
            } else {                                     // lay a row on top
                let h = CGFloat(sum) / free.width
                var x = free.minX
                for cell in row {
                    let w = CGFloat(cell.area) / h
                    out.append(RoomPlacedRect(id: cell.item.id, rect: CGRect(x: x, y: free.minY, width: w, height: h)))
                    x += w
                }
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: max(0, free.height - h))
            }
        }
        while let next = queue.first {
            let side = Double(min(free.width, free.height))
            let candidate = row + [next]
            if row.isEmpty || worst(candidate, side: side) <= worst(row, side: side) {
                row = candidate
                queue = queue.dropFirst()
            } else {
                place(row)
                row = []
            }
        }
        if !row.isEmpty { place(row) }
        return out
    }
}
