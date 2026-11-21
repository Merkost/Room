// Activity pill: one board of per-source posts, hold timers that pause while the person reads,
// a throttled rolling label. Spec: CACHES-RECEIPTS-SPEC.md §8 (amends spec 11 §§2–3).
// Reuses RoomActivityPillState and RoomActivityPillReducer from design/spec/snippets/RoomStateMachines.swift.
import Foundation

nonisolated enum RoomActivityPillState: Equatable, Sendable {
    // Board v4 states (B4 d34, `55-patterns.js` PILL): idle, scan, access, done, made, ok, stopped; plus failed (SPEC).
    case idle(freeBytes: Int64?)                                   // "312 GB free" / "Up to date"; nil -> "Free space unavailable"
    case scanning(tool: Tool, location: String, files: Int, bytes: Int64)
    case needsAccess(folders: Int)                                 // Store only: "Needs access · 2 folders"
    case moved(Receipt)                                            // stage 1 "Moved 8.4 GB to Trash" + Restore
    case made(Receipt)                                             // stage 2 "Made 8.4 GB of room" (only after free space rose)
    case ok(sentence: String)                                      // "Mapped your Mac · 1,428,600 files"
    case stopped(measured: Int, of: Int)                           // "Scan stopped · 7 of 12 folders"
    case failed(action: String)                                    // "Couldn't move 2 items to Trash"

    enum Tool: String, Sendable { case diskMap, caches, developer }
    struct Receipt: Equatable, Sendable { var id: UUID; var sentence: String; var canRestore: Bool }

    /// Priority when several sources report at once: needsAccess > failed > scanning > made > moved > stopped > ok > idle.
    var priority: Int {
        switch self {
        case .needsAccess: 7; case .failed: 6; case .scanning: 5; case .made: 4
        case .moved: 3; case .stopped: 2; case .ok: 1; case .idle: 0
        }
    }

    /// How long the state holds before the pill returns to idle (seconds); nil holds until it changes.
    var hold: TimeInterval? {
        switch self {
        case .ok: 2.6                       // board: "Mapped your Mac" back to idle after 2.6 s
        case .moved, .made: 6
        case .stopped, .failed: 10
        case .idle, .scanning, .needsAccess: nil
        }
    }
}

nonisolated enum RoomActivityPillReducer {
    /// The label rolls at most every 0.5 s, and only to a real location reported by the engine.
    static let labelInterval: TimeInterval = 0.5

    static func merge(_ candidates: [RoomActivityPillState]) -> RoomActivityPillState {
        candidates.max { $0.priority < $1.priority } ?? .idle(freeBytes: nil)
    }
}

nonisolated struct RoomActivityBoard: Equatable, Sendable {
    /// Each producer owns one slot; a new post from the same source replaces its previous one.
    enum Source: String, CaseIterable, Sendable {
        case diskMap, caches, developer, makeRoom, restore, access
    }
    struct Post: Equatable, Sendable {
        var state: RoomActivityPillState
        var postedAt: Date
        var pausedFor: TimeInterval = 0
    }

    private(set) var posts: [Source: Post] = [:]
    private(set) var pausedAt: Date?

    mutating func post(_ state: RoomActivityPillState, from source: Source, at now: Date) {
        posts[source] = Post(state: state, postedAt: now)
    }

    mutating func clear(_ source: Source) { posts[source] = nil }

    /// AP-2: hover over the pill or an open expansion freezes every hold.
    mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        posts = posts.filter { isLive($0.value, now: now) }
        pausedAt = now
    }

    mutating func resume(at now: Date) {
        guard let since = pausedAt else { return }
        for key in posts.keys {
            guard var post = posts[key] else { continue }
            post.pausedFor += max(0, now.timeIntervalSince(max(since, post.postedAt)))
            posts[key] = post
        }
        pausedAt = nil
    }

    private func expiry(_ p: Post) -> Date? {
        p.state.hold.map { p.postedAt.addingTimeInterval($0 + p.pausedFor) }
    }

    func isLive(_ p: Post, now: Date) -> Bool {
        guard pausedAt == nil, let end = expiry(p) else { return true }
        return now < end
    }

    /// The pill shows the highest-priority live post, else idle (AP-1, AP-3).
    func visible(now: Date, idle: RoomActivityPillState) -> RoomActivityPillState {
        let live = posts.values.filter { isLive($0, now: now) }.map(\.state)
        return live.isEmpty ? idle : RoomActivityPillReducer.merge(live)
    }

    /// Everything the expansion lists (§4 "Now" and "Last"), highest priority first.
    func expansion(now: Date) -> [RoomActivityPillState] {
        posts.values.filter { isLive($0, now: now) }.map(\.state).sorted { $0.priority > $1.priority }
    }

    /// One scheduled wake-up, never a polling loop: nil while paused or when nothing will expire.
    func nextExpiry(now: Date) -> Date? {
        guard pausedAt == nil else { return nil }
        return posts.values.compactMap(expiry).filter { $0 > now }.min()
    }
}

/// AP-4: at most one label change per 0.5 s, and only to text the engine reported.
nonisolated struct RoomRollingLabel: Equatable, Sendable {
    static let interval: TimeInterval = 0.5
    private(set) var shown: String?
    private(set) var shownAt: Date?
    private(set) var pending: String?

    /// Returns the text to roll in now, or nil to keep the current label (the latest offer waits as pending).
    mutating func offer(_ text: String, at now: Date) -> String? {
        if text == shown { pending = nil; return nil }
        if let at = shownAt, now.timeIntervalSince(at) < Self.interval { pending = text; return nil }
        shown = text; shownAt = now; pending = nil
        return text
    }

    /// Called by the one scheduled tick at shownAt + interval; rolls the newest pending text, if any.
    mutating func flush(at now: Date) -> String? {
        guard let p = pending else { return nil }
        pending = nil
        return offer(p, at: now)
    }
}

/// Abbreviates a reported path for the pill: home → "~", nothing invented.
nonisolated enum RoomPillPath {
    static func abbreviate(_ path: String, home: String) -> String {
        let h = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !h.isEmpty else { return path }
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }
}
