// Compiled reference (DISK-MAP-SPEC.md §6). Proposed path: Sources/RoomApp/DiskMap/RoomBlueprint.swift.
// The blueprint scan's state, driven by DiskScanProgress events. Honesty rules it enforces:
// a room appears only after its walk finished; a drawn size is never larger than measured; already-drawn rooms
// re-flow at most once a second; the counter is files and bytes so far, never a percentage; a stopped scan's
// total is a lower bound; an unmeasured room on a rescan shows its earlier size, dated, never as "≥" (D-DMB-7).
import Foundation
import RoomCore

nonisolated struct RoomBlueprint: Sendable {
    enum Phase: Equatable, Sendable { case scanning, stopped, done }
    enum RoomState: Equatable, Sendable { case measured, earlier(Date) }

    struct Room: Equatable, Sendable {
        var name: String
        var bytes: Int64
        var kind: String?
        var state: RoomState
        var isPartial = false
    }

    static let reflowInterval: TimeInterval = 1

    let id = UUID()
    let earlier: [String: (bytes: Int64, kind: String?)]   // last map's top level (rescan); empty on a first scan
    let earlierDate: Date?
    private(set) var topLevelTotal: Int?                    // from the walker's first readdir of the root
    private(set) var drawn: [Room] = []                    // measured rooms the layout uses now
    private(set) var pending: [Room] = []                  // finished, waiting for the next re-flow
    private(set) var lastReflow: Date?
    private(set) var beforeLastReflow: [Room] = []
    private(set) var files = 0
    private(set) var bytesSoFar: Int64 = 0
    private(set) var phase: Phase = .scanning

    init(earlier: [String: (bytes: Int64, kind: String?)] = [:], earlierDate: Date? = nil, topLevelTotal: Int? = nil) {
        self.earlier = earlier
        self.earlierDate = earlierDate
        self.topLevelTotal = topLevelTotal
    }

    mutating func setTopLevelTotal(_ n: Int) { topLevelTotal = n }

    /// Counters only move forward: a late, smaller progress event never rolls the number back.
    mutating func progress(files: Int, bytes: Int64) {
        guard phase == .scanning else { return }
        self.files = max(self.files, files)
        bytesSoFar = max(bytesSoFar, bytes)
    }

    /// A top-level child finished. Returns true when the drawn layout changed (the view animates with Motion.page).
    @discardableResult
    mutating func completed(name: String, bytes: Int64, kind: String?, isPartial: Bool = false, at now: Date) -> Bool {
        guard phase == .scanning else { return false }
        pending.append(Room(name: name, bytes: max(0, bytes), kind: kind, state: .measured, isPartial: isPartial))
        return tick(now)
    }

    /// Called on each progress event or a 1 s timer while scanning.
    @discardableResult
    mutating func tick(_ now: Date) -> Bool {
        guard !pending.isEmpty else { return false }
        if let last = lastReflow, now.timeIntervalSince(last) < Self.reflowInterval { return false }
        commit(now)
        return true
    }

    mutating func stop(at now: Date) { guard phase == .scanning else { return }; if !pending.isEmpty { commit(now) }; phase = .stopped }
    mutating func finish(at now: Date) { guard phase == .scanning else { return }; if !pending.isEmpty { commit(now) }; phase = .done }

    private mutating func commit(_ now: Date) {
        beforeLastReflow = rooms
        for room in pending {
            if let i = drawn.firstIndex(where: { $0.name == room.name }) { drawn[i] = room } else { drawn.append(room) }
        }
        pending = []
        lastReflow = now
    }

    var measuredCount: Int { drawn.count }

    /// What the map draws: measured rooms in their places, then (rescan only) the earlier map's other rooms,
    /// hatched at 60 % with their earlier size. On a first scan unmeasured space is the dot grid, so nothing else.
    var rooms: [Room] {
        let measuredNames = Set(drawn.map(\.name))
        guard let date = earlierDate else { return drawn }
        let rest = earlier.filter { !measuredNames.contains($0.key) }
            .map { Room(name: $0.key, bytes: $0.value.bytes, kind: $0.value.kind, state: .earlier(date)) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
        return drawn + rest
    }

    /// The root's total while scanning or after Stop: only what this walk measured, so "≥" is true.
    var totalIsLowerBound: Bool { phase != .done }

    /// DM-23 counter: "214,302 files · 312 GB so far" (16 §8.3 diskmap.readout.counter). No percentage exists.
    func counter(files formatFiles: (Int) -> String, bytes formatBytes: (Int64) -> String) -> String {
        "\(formatFiles(files)) files · \(formatBytes(bytesSoFar)) so far"
    }

    /// DM-25 pill and readout after Stop: "Scan stopped · 7 of 12 rooms measured" (count unknown: "7 rooms measured").
    var stoppedSummary: String {
        if let total = topLevelTotal { return "Scan stopped · \(measuredCount) of \(total) rooms measured" }
        return "Scan stopped · \(measuredCount) rooms measured"
    }
}

nonisolated extension RoomBlueprint.Room {
    var isEarlier: Bool {
        if case .earlier = state { return true }
        return false
    }
}

nonisolated extension RoomBlueprint {
    static func tree(rooms: [Room], maximumTiles: Int) -> RoomTreeNode {
        let ordered = rooms.filter { $0.bytes > 0 }.sorted {
            $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name
        }
        let keep = ordered.count > maximumTiles ? max(0, maximumTiles - 1) : maximumTiles
        let hidden = ordered.dropFirst(keep)
        let children = ordered.prefix(keep).map { room in
            RoomTreeNode(name: room.name, relativePath: room.name, allocatedBytes: room.bytes, fileCount: 0,
                         kindBytes: room.kind.map { [$0: room.bytes] } ?? [:], isPartial: room.isPartial, isDirectory: true,
                         children: [], other: nil)
        }
        let other: RoomTreeNode.OtherGroup? = hidden.isEmpty ? nil : .init(itemCount: hidden.count,
            allocatedBytes: hidden.reduce(0) { $0 + $1.bytes }, isPartial: hidden.contains(where: \.isPartial))
        return RoomTreeNode(name: "", relativePath: "", allocatedBytes: ordered.reduce(0) { $0 + $1.bytes },
                            fileCount: 0, kindBytes: [:], isPartial: true, isDirectory: true,
                            children: children, other: other)
    }
}
