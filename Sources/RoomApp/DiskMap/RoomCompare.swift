import RoomCore
// Compiled reference (DISK-MAP-SPEC.md §7.3). Proposed path: Sources/RoomApp/DiskMap/RoomCompare.swift.
// Compare is two real maps of the same root: the previous tree (≥ 3 days older, RoomTreeCatalog) and the current
// one. The board's "Monday + this week's Room growth" estimate waits for many Rooms (Job D) and is not built here.
import Foundation

nonisolated enum RoomCompare {
    static func isAvailable(current: RoomStoredTree?, previous: RoomStoredTree?) -> Bool {
        guard let current, let previous, current.rootID == previous.rootID, !previous.cancelled else { return false }
        return current.scannedAt.timeIntervalSince(previous.scannedAt) >= RoomTreeCatalog.previousMinimumAge
    }

    struct Row: Equatable, Sendable {
        var name: String
        var then: Int64?             // nil: not in the earlier map's kept children (new, or folded into Other then)
        var now: Int64?
        var change: Int64 { (now ?? 0) - (then ?? 0) }
    }

    /// Children of the same folder in both maps, matched by name; sorted by change, largest growth first
    /// (the VoiceOver table "Folder, Monday, Now, Change"). Other groups are not matched: their members differ.
    static func rows(then: RoomTreeNode, now: RoomTreeNode) -> [Row] {
        var byName: [String: Row] = [:]
        for c in then.children { byName[c.name] = Row(name: c.name, then: c.allocatedBytes, now: nil) }
        for c in now.children { byName[c.name, default: Row(name: c.name, then: nil, now: nil)].now = c.allocatedBytes }
        return byName.values.sorted { $0.change != $1.change ? $0.change > $1.change : $0.name < $1.name }
    }

    /// 16 §8.3 diskmap.compare.readout: "suby-kmp: 18.4 GB on Mon 9 Nov → 21.6 GB now (+3.2 GB)".
    /// A side the map did not keep says "not listed", never 0 GB.
    static func readout(_ row: Row, thenLabel: String, format: (Int64) -> String) -> String {
        let a = row.then.map(format) ?? "not listed"
        let b = row.now.map(format) ?? "not listed"
        guard row.then != nil, row.now != nil else { return "\(row.name): \(a) on \(thenLabel) → \(b) now" }
        let sign = row.change > 0 ? "+" : row.change < 0 ? "−" : "±"
        return "\(row.name): \(a) on \(thenLabel) → \(b) now (\(sign)\(format(abs(row.change))))"
    }
}

/// The divider (06 §9, 19 §5): press jumps in 120 ms, drag follows 1:1, a flick > 0.5 pt/ms glides 360 ms to the
/// edge it was thrown at, ←/→ move 5 %, Home/End go to the edges. Reduce Motion: every move is a jump.
nonisolated struct RoomCompareDivider: Equatable, Sendable {
    enum Move: Equatable, Sendable { case instant, jump120, glide360 }
    enum Key: Sendable { case left, right, home, end }
    static let flickThreshold = 0.5          // pt per ms
    static let keyStep = 5.0                 // percent

    private(set) var position = 50.0         // percent of the map width from the left
    var reduceMotion = false

    private mutating func set(_ value: Double) { position = min(100, max(0, value)) }
    private func motion(_ m: Move) -> Move { reduceMotion ? .instant : m }

    mutating func press(atPercent x: Double) -> Move { set(x); return motion(.jump120) }
    mutating func drag(toPercent x: Double) -> Move { set(x); return .instant }
    mutating func release(velocityPtPerMS v: Double) -> Move {
        guard abs(v) > Self.flickThreshold else { return .instant }
        set(v > 0 ? 100 : 0)
        return motion(.glide360)
    }
    mutating func key(_ k: Key) -> Move {
        switch k {
        case .left: set(position - Self.keyStep)
        case .right: set(position + Self.keyStep)
        case .home: set(0)
        case .end: set(100)
        }
        return .instant                       // keyboard never animates (03, 14 §6)
    }
}
