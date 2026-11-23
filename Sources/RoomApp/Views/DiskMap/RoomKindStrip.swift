import RoomCore
// Compiled reference (DISK-MAP-SPEC.md §7.4). Proposed path: Sources/RoomApp/DiskMap/RoomKindStrip.swift (pure half).
// One dataset, two honest views (06 §11, 19 D-26): a 12 pt Bar or a Dots field (board v4 `dotField`, `niceUnit`).
// Reuses RoomPure.dotAlloc from design/spec/snippets/RoomPure.swift; no second rounding rule.
import CoreGraphics
import Foundation

nonisolated enum RoomKindStrip {
    static let barMinimumSegment: CGFloat = 6
    static let barGap: CGFloat = 2

    /// Kind totals of a folder in StorageKind order, zero kinds dropped.
    static func totals(_ node: RoomTreeNode) -> [(kind: String, bytes: Int64)] {
        StorageKind.allCases.compactMap { k in
            guard let v = node.kindBytes[k.rawValue], v > 0 else { return nil }
            return (k.rawValue, v)
        }
    }

    /// Segment widths that fill `width` exactly: proportional, every segment at least 6 pt (when they fit),
    /// 2 pt gaps. A segment can be wider than its share only because of the minimum; the legend carries the number.
    static func bar(_ parts: [(kind: String, bytes: Int64)], width: CGFloat) -> [(kind: String, width: CGFloat)] {
        let parts = parts.filter { $0.bytes > 0 }
        guard !parts.isEmpty else { return [] }
        let available = width - barGap * CGFloat(parts.count - 1)
        guard available > 0 else { return [] }
        var fixed = Set<Int>()
        var widths = [CGFloat](repeating: 0, count: parts.count)
        while true {
            let flexible = parts.indices.filter { !fixed.contains($0) }
            let room = available - CGFloat(fixed.count) * barMinimumSegment
            let sum = flexible.reduce(0.0) { $0 + Double(parts[$1].bytes) }
            var changed = false
            for i in flexible {
                let w = sum > 0 ? CGFloat(Double(parts[i].bytes) / sum) * room : 0
                if w < barMinimumSegment && CGFloat(fixed.count + 1) * barMinimumSegment <= available {
                    fixed.insert(i); changed = true
                } else { widths[i] = w }
            }
            if !changed { break }
        }
        for i in fixed { widths[i] = barMinimumSegment }
        return zip(parts, widths).map { ($0.kind, $1) }
    }

    /// Board `niceUnit`: the smallest step ≥ total / 220 dots.
    static let unitLadderGB: [Double] = [0.1, 0.2, 0.25, 0.5, 1, 2, 4, 5, 10, 20]
    static func dotUnit(totalGB: Double, targetDots: Double = 220) -> Double {
        let x = totalGB / targetDots
        return unitLadderGB.first { x <= $0 } ?? 50
    }

    struct DotField: Equatable, Sendable {
        var unitGB: Double
        var counts: [String: Int]       // kind raw → dots (RoomPure.dotAlloc, each kind on its own)
        var underOneDot: [String]       // measured kinds below half a dot: legend and VoiceOver, never "0"
        var columns: Int
        static let rows = 6, pitch: CGFloat = 10, radius: CGFloat = 3.5
        var size: CGSize { CGSize(width: CGFloat(columns) * Self.pitch + 2, height: CGFloat(Self.rows) * Self.pitch + 2) }
    }

    static func dots(_ parts: [(kind: String, bytes: Int64)]) -> DotField {
        let total = Double(parts.reduce(0) { $0 + $1.bytes }) / 1e9
        let unit = dotUnit(totalGB: total)
        let alloc = RoomPure.dotAlloc(parts.map { (key: $0.kind, gb: Double($0.bytes) / 1e9) }, unit: unit)
        let n = RoomPure.dotSum(alloc)
        return DotField(unitGB: unit, counts: Dictionary(uniqueKeysWithValues: alloc.map { ($0.key, $0.dots) }),
                        underOneDot: alloc.filter { $0.dots == 0 && $0.gb > 0 }.map(\.key),
                        columns: Int((Double(n) / Double(DotField.rows)).rounded(.up)))
    }

    /// Legend: up to four kinds with their share, the rest as "+N" (06 §11).
    static func legend(_ parts: [(kind: String, bytes: Int64)]) -> (shown: [String], more: Int) {
        let sorted = parts.filter { $0.bytes > 0 }.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.kind < $1.kind }
        return (sorted.prefix(4).map(\.kind), max(0, sorted.count - 4))
    }
}
