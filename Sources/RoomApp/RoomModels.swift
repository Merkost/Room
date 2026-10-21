import Foundation

enum RoomDestination: Hashable { case clean, memory, disk, developer, activity }

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
    var isAvailable: Bool { eligibleBytes > 0 && selectableCount > 0 }
}

struct RoomProtectedSource: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let reason: String
    let bytes: Int64
}

struct RoomActivity: Identifiable, Sendable {
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

struct RoomActivityItem: Identifiable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let message: String
    let isRestored: Bool
    let canRestore: Bool
}
