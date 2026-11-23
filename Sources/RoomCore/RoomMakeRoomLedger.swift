// Two-stage Make room: ledger, Trash presence, copy, History summary, debug simulation.
// Spec: rest-spec/C-caches-receipts/CACHES-RECEIPTS-SPEC.md §5–§7 (amends spec 07 §6, 11 §9).
// Supersedes the ledger half of design/spec/snippets/RoomStateMachines.swift (RoomRoomLedger*),
// reuses its RoomTrashObservation unchanged. Pure value types; the app's @Observable store owns one array.
import Foundation

package nonisolated struct RoomTrashObservation: Sendable {
    package var presentBytes: Int64
    package var goneBytes: Int64
    package var restoredBytes: Int64
    package var canObserve: Bool

    package init(presentBytes: Int64, goneBytes: Int64, restoredBytes: Int64, canObserve: Bool) {
        self.presentBytes = presentBytes
        self.goneBytes = goneBytes
        self.restoredBytes = restoredBytes
        self.canObserve = canObserve
    }
}

// MARK: - Capacity sample

/// One reading of `volumeAvailableCapacity` (spec 19 D-5) with the device of the volume it describes.
package nonisolated struct RoomCapacitySample: Equatable, Sendable {
    package var freeBytes: Int64
    package var device: UInt64
    package var at: Date

    package init(freeBytes: Int64, device: UInt64, at: Date) {
        self.freeBytes = freeBytes
        self.device = device
        self.at = at
    }
}

// MARK: - Ledger entry

package nonisolated struct RoomMakeRoomEntry: Codable, Equatable, Sendable, Identifiable {
    package enum Stage: String, Codable, Sendable {
        case inTrash, partlyEmptied, emptied, emptiedNoGain, restored, unobservable
    }
    package var id: UUID                    // == ActivityReceipt.id
    package var movedAt: Date
    package var movedBytes: Int64           // ActivityReceipt.trashedBytes when the entry is made
    package var itemCount: Int              // ActivityReceipt.trashedCount
    package var freeAtMove: Int64?          // nil: no baseline (1.x receipt, capacity unreadable, crash) -> never stage 2
    package var volumeDevice: UInt64?       // device of the moved items; nil -> never stage 2
    package var lastFree: Int64?
    package var lastChecked: Date
    package var lastChangedAt: Date
    package var goneBytes: Int64 = 0
    package var restoredBytes: Int64 = 0
    package var observedGain: Int64 = 0
    package var attributionUncertain = false
    package var stage: Stage = .inTrash
    package var closed = false              // kept separately so a closed entry keeps its last sentence

    package var stillInTrashBytes: Int64 { max(0, movedBytes - goneBytes - restoredBytes) }
    /// Entries Room still checks: items may still be in Trash.
    package var isObserved: Bool { !closed && (stage == .inTrash || stage == .partlyEmptied || stage == .unobservable) }

    /// Stage 1. `sample` is taken immediately after `CacheEngine.clean` returns; nil keeps the entry honest at stage 1 forever.
    package static func stageOne(receiptID: UUID, movedAt: Date, movedBytes: Int64, itemCount: Int,
                         itemsDevice: UInt64?, sample: RoomCapacitySample?) -> RoomMakeRoomEntry? {
        guard movedBytes > 0, itemCount > 0 else { return nil }
        let sameVolume = sample != nil && itemsDevice != nil && sample?.device == itemsDevice
        return RoomMakeRoomEntry(id: receiptID, movedAt: movedAt, movedBytes: movedBytes, itemCount: itemCount,
            freeAtMove: sameVolume ? sample?.freeBytes : nil, volumeDevice: sameVolume ? itemsDevice : nil,
            lastFree: sameVolume ? sample?.freeBytes : nil, lastChecked: sample?.at ?? movedAt, lastChangedAt: movedAt)
    }

    /// A receipt found on disk with no entry (1.x, or a crash before the entry was saved). Never claims stage 2.
    package static func adopted(receiptID: UUID, movedAt: Date, movedBytes: Int64, itemCount: Int) -> RoomMakeRoomEntry? {
        guard movedBytes > 0, itemCount > 0 else { return nil }
        return RoomMakeRoomEntry(id: receiptID, movedAt: movedAt, movedBytes: movedBytes, itemCount: itemCount,
            freeAtMove: nil, volumeDevice: nil, lastFree: nil, lastChecked: movedAt, lastChangedAt: movedAt)
    }
}

// MARK: - The ledger

package nonisolated enum RoomMakeRoomLedger {
    package static let attributionFloor = 0.5            // stage 2 needs observedGain >= 50 % of goneBytes
    package static let noiseBytes: Int64 = 200_000_000   // rises at or under 200 MB are noise
    package static let maxCheckGap: TimeInterval = 600   // a rise counts only if the previous check is <= 10 min old
    package static let closeAfter: TimeInterval = 30 * 86_400
    package static let checkInterval: TimeInterval = 60

    /// One check: one capacity sample plus one observation per entry Room could look at.
    /// `sample == nil` (capacity unreadable) changes nothing, so the next readable check still sees what left.
    /// A missing observation (presence unknown this time) leaves that entry untouched.
    package static func advance(_ entries: [RoomMakeRoomEntry], observations: [UUID: RoomTrashObservation],
                        sample: RoomCapacitySample?, now: Date) -> [RoomMakeRoomEntry] {
        guard let sample else { return entries }
        func attributable(_ e: RoomMakeRoomEntry) -> Bool {
            let gap = now.timeIntervalSince(e.lastChecked)
            return e.movedBytes > noiseBytes && e.freeAtMove != nil && e.lastFree != nil && e.volumeDevice == sample.device
                && gap >= 0 && gap <= maxCheckGap
        }
        func newly(_ e: RoomMakeRoomEntry) -> Int64 {
            guard e.isObserved, let o = observations[e.id], o.canObserve else { return 0 }
            return max(0, o.goneBytes - e.goneBytes)
        }
        // Share one rise only between entries that could have caused it.
        let totalNewly = entries.filter(attributable).reduce(Int64(0)) { $0 + newly($1) }
        func closing(_ entry: RoomMakeRoomEntry) -> RoomMakeRoomEntry {
            var c = entry
            // An entry Room could not observe for 30 days stops being checked, so the 60 s loop always ends.
            if !c.closed, !c.isObserved || observations[c.id] == nil,
               now.timeIntervalSince(c.lastChangedAt) > closeAfter { c.closed = true }
            return c
        }
        func step(_ e: RoomMakeRoomEntry) -> RoomMakeRoomEntry {
            var next = e
            guard e.isObserved, now >= e.lastChecked, let o = observations[e.id] else { return next }
            next.lastChecked = now
            next.lastFree = e.volumeDevice == sample.device ? sample.freeBytes : nil
            guard o.canObserve else {
                if e.stage == .inTrash { next.stage = .unobservable; next.lastChangedAt = now }
                return next
            }
            let mine = newly(e)
            if mine > 0 {
                if attributable(e), let before = e.lastFree, totalNewly > 0 {
                    let rise = sample.freeBytes - before
                    if rise > noiseBytes {
                        let share = Int64((Double(rise) * Double(mine) / Double(totalNewly)).rounded(.down))
                        next.observedGain = min(o.goneBytes, e.observedGain + min(mine, share))
                    }
                } else if e.freeAtMove != nil, now.timeIntervalSince(e.lastChecked) > maxCheckGap {
                    next.attributionUncertain = true
                }
            }
            next.goneBytes = o.goneBytes
            next.restoredBytes = o.restoredBytes
            if o.presentBytes == 0, o.goneBytes == 0, o.restoredBytes > 0 { next.stage = .restored }
            else if o.presentBytes == 0, o.goneBytes > 0 {
                next.stage = Double(next.observedGain) >= attributionFloor * Double(o.goneBytes) && next.observedGain > 0
                    ? .emptied : .emptiedNoGain
            } else if o.goneBytes > 0 { next.stage = .partlyEmptied }
            else { next.stage = .inTrash }
            if next.stage != e.stage || next.goneBytes != e.goneBytes || next.restoredBytes != e.restoredBytes {
                next.lastChangedAt = now
            }
            return next
        }
        return entries.map { closing(step($0)) }
    }

    package static let retention: TimeInterval = 90 * 86_400

    /// Drops closed entries last changed over ~90 days ago so `ledger.json` stays under its size cap.
    /// Open entries and entries whose receipt can still restore are never dropped.
    package static func pruned(_ entries: [RoomMakeRoomEntry], now: Date,
                               canRestore: (UUID) -> Bool) -> [RoomMakeRoomEntry] {
        entries.filter { e in
            !(e.closed && !e.isObserved && now.timeIntervalSince(e.lastChangedAt) > retention && !canRestore(e.id))
        }
    }

    /// When the 60 s check runs at all (CA-18): only while something may still be in Trash.
    package static func needsChecks(_ entries: [RoomMakeRoomEntry]) -> Bool {
        entries.contains { $0.isObserved && $0.stage != .unobservable }
    }
}

// MARK: - Trash presence (spec 07 §6.3, tightened)

package nonisolated enum RoomTrashItemState: Equatable, Sendable {
    case present, gone, putBack, unknown, unobservable
}

/// What `lstat` returned for one path. `errno` other than ENOENT never means "gone".
package nonisolated enum RoomStatProbe: Equatable, Sendable {
    case object(device: UInt64, inode: UInt64, mode: UInt16)
    case missing                     // ENOENT / ENOTDIR
    case failed(Int32)               // EPERM, EACCES, EIO, …
}

/// What resolving the Store's exact Trash-item bookmark returned (without starting access).
package nonisolated enum RoomBookmarkProbe: Equatable, Sendable {
    case noBookmark
    case resolved(path: String)
    case noSuchFile                  // NSFileNoSuchFileError / NSFileReadNoSuchFileError only
    case failed                      // any other error, including volume unavailable
}

package nonisolated enum RoomTrashPresence {
    /// Direct edition. `trashIdentity` falls back to `originalIdentity` because a same-volume move keeps device and inode.
    package static func direct(hasTrashURL: Bool, trash: RoomStatProbe, original: RoomStatProbe,
                       trashIdentity: (device: UInt64, inode: UInt64, mode: UInt16)?,
                       originalIdentity: (device: UInt64, inode: UInt64, mode: UInt16)) -> RoomTrashItemState {
        guard hasTrashURL else { return .unobservable }
        let expected = trashIdentity ?? originalIdentity
        switch trash {
        case .failed: return .unknown
        case .object(let d, let i, let m) where d == expected.device && i == expected.inode:
            return m == expected.mode ? .present : .unknown
        case .object, .missing:
            switch original {
            case .object(let d, let i, let m)
                where d == originalIdentity.device && i == originalIdentity.inode:
                return m == originalIdentity.mode ? .putBack : .unknown
            case .failed: return .unknown
            case .object, .missing: return .gone
            }
        }
    }

    /// Store edition. Only the exact bookmark is consulted; no Trash folder grant is ever requested.
    package static func store(_ probe: RoomBookmarkProbe, trashPath: String?, originalPath: String,
                      trashDirectories: [String]) -> RoomTrashItemState {
        switch probe {
        case .noBookmark: return .unobservable
        case .failed: return .unknown
        case .noSuchFile: return .gone
        case .resolved(let path):
            if path == trashPath { return .present }
            if path == originalPath { return .putBack }
            if trashDirectories.contains(where: { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) { return .present }
            return .unknown          // moved elsewhere by the person: Room claims nothing
        }
    }

    /// Fold one receipt's trashed items. Any unknown item skips the entry this check; any unobservable item makes the
    /// whole entry unobservable (Room says less rather than guess about the rest).
    package static func observation(_ items: [(bytes: Int64, state: RoomTrashItemState)]) -> RoomTrashObservation? {
        guard !items.isEmpty else { return nil }
        if items.contains(where: { $0.state == .unknown }) { return nil }
        if items.contains(where: { $0.state == .unobservable }) {
            return RoomTrashObservation(presentBytes: 0, goneBytes: 0, restoredBytes: 0, canObserve: false)
        }
        func sum(_ s: RoomTrashItemState) -> Int64 { items.filter { $0.state == s }.reduce(0) { $0 + $1.bytes } }
        return RoomTrashObservation(presentBytes: sum(.present), goneBytes: sum(.gone),
                                    restoredBytes: sum(.putBack), canObserve: true)
    }
}

// MARK: - Copy (16 §5 with this spec's deltas)

package nonisolated enum RoomMakeRoomCopy {
    /// The one sentence for the pill, receipt total, Overview receipt line and History card.
    /// "Made" appears only for an observed gain above the noise band.
    package static func headline(_ e: RoomMakeRoomEntry, format: (Int64) -> String) -> String {
        let made = e.observedGain > 0   // only ever set from a rise above the noise band (advance)
        switch e.stage {
        case .inTrash, .unobservable:
            return "Moved \(format(e.movedBytes)) to Trash"
        case .partlyEmptied:
            return made
                ? "Made \(format(e.observedGain)) of room · \(format(e.stillInTrashBytes)) still in Trash"
                : "Moved \(format(e.movedBytes)) to Trash · \(format(e.stillInTrashBytes)) still in Trash"
        case .emptied where made:
            return "Made \(format(e.observedGain)) of room"
        case .emptied, .emptiedNoGain:
            if e.attributionUncertain { return "These left the Trash while Room was closed" }
            if e.freeAtMove == nil { return "Gone from Trash" }
            if e.movedBytes <= RoomMakeRoomLedger.noiseBytes { return "Gone from Trash · too small for Room to see the change" }
            return "Gone from Trash · the space hasn't come back yet"
        case .restored:
            return "Put back \(e.itemCount) \(e.itemCount == 1 ? "item" : "items")"
        }
    }

    /// Receipt footer word (CA-21): nil means Restore is offered.
    package static func footerWord(_ e: RoomMakeRoomEntry?, receiptCanRestore: Bool) -> String? {
        guard receiptCanRestore else { return e?.stage == .restored ? "Restored" : "Nothing to restore" }
        switch e?.stage {
        case .restored: return "Restored"
        case .emptied, .emptiedNoGain: return "Gone"
        default: return nil
        }
    }
}

// MARK: - History summary (CA-23)

package nonisolated struct RoomHistorySummary: Equatable, Sendable {
    package var madeBytes: Int64          // stage-2 gains only
    package var madeCount: Int
    package var since: Date?
    package var stillInTrashBytes: Int64  // observed present only; unobservable entries are in neither figure
    package var badge: Int                // AP-5: receipts with items Room saw still in Trash

    package static func make(_ entries: [RoomMakeRoomEntry]) -> RoomHistorySummary {
        let gains = entries.filter { $0.observedGain > 0 && ($0.stage == .emptied || $0.stage == .partlyEmptied) }
        let present = entries.filter { !$0.closed && ($0.stage == .inTrash || $0.stage == .partlyEmptied) }
        return RoomHistorySummary(madeBytes: gains.reduce(0) { $0 + $1.observedGain }, madeCount: gains.count,
            since: gains.map(\.movedAt).min(), stillInTrashBytes: present.reduce(0) { $0 + $1.stillInTrashBytes },
            badge: present.count)
    }

    package func header(format: (Int64) -> String, month: (Date) -> String) -> String? {
        if madeCount > 0, let since {
            let base = "Room made \(format(madeBytes)) of room since \(month(since)), across \(madeCount) \(madeCount == 1 ? "cleanup" : "cleanups")"
            return stillInTrashBytes > 0 ? base + ", and moved \(format(stillInTrashBytes)) to Trash that is still there" : base
        }
        if stillInTrashBytes > 0 { return "Moved \(format(stillInTrashBytes)) to Trash that is still there" }
        return nil
    }

    package static func badgeText(_ n: Int) -> String? { n <= 0 ? nil : n > 9 ? "9+" : String(n) }
}
