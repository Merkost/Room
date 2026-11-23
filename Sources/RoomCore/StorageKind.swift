// Compiled reference (DISK-MAP-SPEC.md §3.1). Proposed path: Sources/RoomCore/StorageKind.swift (public in the app).
// The seven exclusive board kinds, FD-10 (02 §6). One file lands in exactly one kind, so kind totals are sums,
// never a subtraction of overlapping figures (today's hiddenAllocatedBytes overlaps every category).
// The app version takes `StorageCategory` directly; this reference takes its rawValue so it compiles alone.
import Foundation

public nonisolated enum StorageKind: String, CaseIterable, Codable, Sendable {
    case developer, media, documents, apps, archives, system, hidden

    /// FD-10 table. Hidden only wins for `systemOther`: a hidden `.gradle/caches` file is still Developer.
    /// Returns nil for an unknown category so a future category can never be silently filed under System.
    public static func kind(categoryRaw: String, isHidden: Bool) -> StorageKind? {
        switch categoryRaw {
        case "cachesBuilds", "agents": .developer
        case "applications": .apps
        case "archives": .archives
        case "media": .media
        case "documents": .documents
        case "systemOther": isHidden ? .hidden : .system
        default: nil
        }
    }

    public static func kind(category: StorageCategory, isHidden: Bool) -> StorageKind? {
        kind(categoryRaw: category.rawValue, isHidden: isHidden)
    }

    /// 16 §8 kind names (not masked by Hide, PE-24).
    public var title: String {
        switch self {
        case .developer: "Developer"
        case .media: "Media"
        case .documents: "Documents"
        case .apps: "Apps"
        case .archives: "Archives"
        case .system: "System & other"
        case .hidden: "Hidden files"
        }
    }

    /// One line for the hover help: what a kind holds when its name alone could mislead ("Hidden" is not "hidden by Room").
    public var explanation: String? {
        switch self {
        case .hidden: "Folders whose names start with a dot, like .gradle or .npm. Finder hides them; Room still measures them."
        default: nil
        }
    }

    /// The kind a mixed folder is drawn in: most bytes, ties broken by case order. nil when nothing was measured.
    public static func dominant(_ bytes: [String: Int64]) -> StorageKind? {
        var best: (StorageKind, Int64)?
        for kind in allCases {
            let value = bytes[kind.rawValue] ?? 0
            guard value > 0 else { continue }
            if best == nil || value > best!.1 { best = (kind, value) }
        }
        return best?.0
    }
}
