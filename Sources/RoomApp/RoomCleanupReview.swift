import Foundation

/// Availability is queried on map selection changes. Index eligible items and their enclosing folders once per report.
nonisolated struct RoomMapCleanupPathIndex {
    private let items: Set<String>
    private let folders: Set<Substring>

    init(_ paths: [String]) {
        items = Set(paths)
        var enclosingFolders: Set<Substring> = []
        for path in items {
            // Match the character boundaries used by String.hasPrefix in the review.
            for index in path.indices where path[index] == "/" {
                let folder = index == path.startIndex ? path[...index] : path[..<index]
                enclosingFolders.insert(folder)
            }
        }
        folders = enclosingFolders
    }

    func contains(path: String, includesContents: Bool) -> Bool {
        items.contains(path) || (includesContents && folders.contains(path[...]))
    }
}

nonisolated struct RoomMapCleanup: Equatable, Sendable {
    let location: URL
    let reportID: UUID
    let rows: [RoomCleanupReview.Row]
    var includesContents = true

    func includes(_ entryIDs: Set<UUID>) -> Bool {
        !entryIDs.isEmpty && entryIDs.isSubset(of: Set(rows.flatMap(\.entryIDs)))
    }

    func matches(_ url: URL, path: String) -> Bool {
        Self.matches(url, path: path, includesContents: includesContents)
    }

    static func matches(_ url: URL, path: String, includesContents: Bool) -> Bool {
        url.path == path || (includesContents && url.path.hasPrefix(path == "/" ? "/" : path + "/"))
    }
}

nonisolated enum RoomMapCleanupAction: Equatable {
    case check, checking, review, empty
}

nonisolated struct RoomCleanupReview: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        var id: String                 // RoomSource.id (family)
        var name: String
        var bytes: Int64               // eligibleBytes
        var consequence: String        // user's words, e.g. "Rebuilt by ./gradlew on next sync"
        var entryIDs: Set<UUID>
        var parentFolders: Set<String> // Store: exact parents from authorizationLocations
        var pickedBytes: Int64? = nil
        var location: String? = nil

        var selectedBytes: Int64 { pickedBytes ?? bytes }
    }
    enum Phase: Equatable, Sendable { case reviewing, preparingAccess, moving, finished }
    enum Commit: Equatable, Sendable {
        case move(Int64)
        case selectAtLeastOne
        case allow(Int)                // "Allow %d folders to continue"
        case checkingAccess
        case moving
    }

    var rows: [Row]
    var selected: Set<String>
    var store: Bool
    var allowed: Set<String> = []
    var phase: Phase = .reviewing

    var selectedRows: [Row] { rows.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedRows.reduce(0) { $0 + $1.selectedBytes } }
    var offeredBytes: Int64 { rows.reduce(0) { $0 + $1.bytes } }
    var selectedEntryIDs: Set<UUID> { selectedRows.reduce(into: Set<UUID>()) { $0.formUnion($1.entryIDs) } }
    var requiredFolders: Set<String> { store ? selectedRows.reduce(into: Set<String>()) { $0.formUnion($1.parentFolders) } : [] }
    var missingFolders: Set<String> { requiredFolders.subtracting(allowed) }

    var commit: Commit {
        switch phase {
        case .moving, .finished: return .moving
        case .preparingAccess: return .checkingAccess
        case .reviewing:
            if selectedBytes <= 0 { return .selectAtLeastOne }
            if store, !missingFolders.isEmpty { return .allow(missingFolders.count) }
            return .move(selectedBytes)
        }
    }
    var canCommit: Bool { if case .move = commit { return true }; return false }
    var canCancel: Bool { phase != .moving }

    /// Toggling in the sheet is live (CA-10) and keeps grants that are still needed (narrowing never re-asks).
    mutating func toggle(_ id: String) {
        guard phase == .reviewing, rows.contains(where: { $0.id == id }) else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        allowed.formIntersection(requiredFolders)
    }

    /// "Before you move" (CA-11): selected consequences deduplicated in row order, then the two fixed lines, then kept safe.
    func beforeYouMove(keptBytes: Int64?, keptExample: String?, format: (Int64) -> String) -> [String] {
        var seen = Set<String>(); var lines: [String] = []
        for r in selectedRows where !r.consequence.isEmpty && seen.insert(r.consequence).inserted { lines.append(r.consequence) }
        lines.append("They wait in Trash. The space comes back when you empty it; Room never empties Trash.")
        if let keptBytes, keptBytes > 0 {
            lines.append("Kept safe: \(format(keptBytes))" + (keptExample.map { ", including \($0)." } ?? "."))
        }
        return lines
    }

    /// CA-13: a row ticks only when the engine has reported every one of its entries as saved in the receipt.
    func tickedRows(reported: Set<UUID>) -> Set<String> {
        Set(selectedRows.filter { !$0.entryIDs.isEmpty && $0.entryIDs.isSubset(of: reported) }.map(\.id))
    }
}

/// Store: which existing grants survive a selection change and which folders still need Allow….
nonisolated enum RoomStoreGrantPlan {
    static func reconcile(required: Set<String>, granted: Set<String>) -> (keep: Set<String>, release: Set<String>, ask: Set<String>) {
        (granted.intersection(required), granted.subtracting(required), required.subtracting(granted))
    }
}

/// The review sheet's words (nav-v3): "Move 22 GB to Trash?" and one plain line about what happens next.
nonisolated enum RoomReviewWords {
    enum Kind: Sendable { case caches, cachesInFolder, ownFolders, buildFolders }

    static func title(_ bytes: Int64, hidden: Bool) -> String {
        hidden ? "Move ••• to Trash?" : "Move \(RoomFormat.gb(bytes)) to Trash?"
    }

    static func body(_ kind: Kind) -> String {
        switch kind {
        case .caches:
            "Rebuildable caches. They stay in Trash until you empty it, and History can put all of it back."
        case .cachesInFolder:
            "Rebuildable caches inside the folder you picked. They stay in Trash until you empty it, and History can put them back."
        case .ownFolders:
            "These are your own folders, not caches. They stay in Trash until you empty it, and History can put them back."
        case .buildFolders:
            "Folders your project tools make again when you install or build. They stay in Trash until you empty it, and History can put them back."
        }
    }
}
