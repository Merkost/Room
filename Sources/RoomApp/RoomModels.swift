import Foundation

nonisolated enum RoomDestination: String, Hashable, Sendable {
    case overview, clean, memory, disk, developer
    /// Room 1.2 (nav-v3): History and Settings are places in the window, at the bottom of the sidebar.
    case history, settings
}

enum RoomCacheScanScope: String, CaseIterable, Identifiable, Sendable {
    case full, quick
    var id: String { rawValue }
    var title: String { self == .full ? "Full scan" : "Quick scan" }
}

struct RoomHeldReason: Identifiable, Sendable {
    var id: String { reason }
    let reason: String
    let bytes: Int64
    let count: Int
}

struct RoomSourceEntry: Identifiable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let bytes: Int64
    let reason: String?
}

enum RoomCategory: String, CaseIterable, Identifiable, Sendable {
    case agents, developer, apps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .agents: "Agents"
        case .developer: "Developer"
        case .apps: "Apps"
        }
    }
}

struct RoomSource: Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let path: String
    let notes: String
    let symbol: String
    let category: RoomCategory
    let bytes: Int64
    let eligibleBytes: Int64
    let entryCount: Int
    let selectableCount: Int
    let blockedReason: String?
    let isPartial: Bool
    let heldReasons: [RoomHeldReason]
    let largestEntries: [RoomSourceEntry]
    let isInspectionOnly: Bool
    /// Explicit impacts for eligible cleanup units, separate from mixed notes.
    var cleanupConsequences: [String] = []
    /// What moving this source's recently used items costs.
    var recentConsequences: [String] = []
    var isAvailable: Bool { eligibleBytes > 0 && selectableCount > 0 }
}

/// A place on Caches that is not ticked for you: used recently (tickable) or open right now (not yet).
struct RoomCacheRow: Identifiable, Sendable, Equatable {
    /// A selection key for recent rows, so a place's old and recent parts are ticked separately.
    let id: String
    let sourceID: String
    let name: String
    let path: String
    let note: String
    let bytes: Int64

    static func recentKey(_ sourceID: String) -> String { "recent:" + sourceID }
    static func isRecentKey(_ key: String) -> Bool { key.hasPrefix("recent:") }

    static func recentNote(newest: Date, now: Date) -> String {
        switch max(0, Int(now.timeIntervalSince(newest) / 86_400)) {
        case 0: "used today"
        case 1: "used yesterday"
        case let days: "used \(days) days ago"
        }
    }

    /// The engine's first sentence: "Xcode is running".
    static func inUseNote(_ reason: String) -> String {
        String(reason.prefix { $0 != "." })
    }
}

struct RoomProtectedSource: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let reason: String
    let bytes: Int64
}

nonisolated struct RoomActivity: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let bytes: Int64
    let itemCount: Int
    let restoredCount: Int
    let errorCount: Int
    let canRestore: Bool
    let title: String
    let details: [RoomActivityItem]
}

nonisolated struct RoomActivityItem: Identifiable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let message: String
    let isRestored: Bool
    let canRestore: Bool
    var bytes: Int64 = 0
    var source: String?
}
