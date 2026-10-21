import Foundation

public enum Eligibility: Codable, Equatable, Sendable {
    case eligible
    case blocked(String)

    public var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }

    public var reason: String? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }
}

public struct CacheEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let byteCount: Int64
    public let modifiedAt: Date
    public let eligibility: Eligibility
    public let fileCount: Int
}

public struct CacheGroup: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let category: String
    public let rootURL: URL
    public let consequence: String
    public let entries: [CacheEntry]
    public let issues: [ScanIssue]
    public var isPartial: Bool = false
    public var isInspectionOnly: Bool? = nil
    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.byteCount } }
    public var eligibleBytes: Int64 { entries.filter(\.eligibility.isEligible).reduce(0) { $0 + $1.byteCount } }
    public var eligibleEntries: [CacheEntry] { entries.filter(\.eligibility.isEligible) }
}

public struct ProtectedData: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let byteCount: Int64
    public let reason: String
    public let isPartial: Bool
}

public struct ScanIssue: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let message: String

    public init(url: URL, message: String) {
        id = UUID()
        self.url = url
        self.message = message
    }
}

public struct VolumeInfo: Codable, Equatable, Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64
    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
}

public struct ScanReport: Codable, Equatable, Sendable {
    public let id: UUID
    public let scannedAt: Date
    public let groups: [CacheGroup]
    public let protectedData: [ProtectedData]
    public let issues: [ScanIssue]
    public let volume: VolumeInfo
    public let cancelled: Bool
    public var isPartial: Bool { cancelled || !issues.isEmpty || groups.contains(where: \.isPartial) || protectedData.contains(where: \.isPartial) }
    public var totalBytes: Int64 { groups.reduce(0) { $0 + $1.totalBytes } }
    public var eligibleBytes: Int64 { groups.reduce(0) { $0 + $1.eligibleBytes } }
    public var eligibleEntries: [CacheEntry] { groups.flatMap(\.eligibleEntries) }
}

/// Incremental reports are informational; cleanup IDs are minted only at completion.
public struct CacheScanProgress: Sendable {
    public let completedRoots: Int
    public let totalRoots: Int
    public let currentPath: String
    public let partialReport: ScanReport
}

/// Device and inode distinguish a replaced file from the item the user reviewed.
public struct FileIdentity: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let changedSeconds: Int64
    public let changedNanoseconds: Int64
    public let byteCount: Int64
    public let mode: UInt16
}

public enum ActivityStatus: String, Codable, Sendable {
    case pending
    case trashed
    case restored
    case failed
}

public struct ActivityItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let rootID: String
    public let originalURL: URL
    public var trashURL: URL?
    public let byteCount: Int64
    public let originalIdentity: FileIdentity
    public let rootIdentity: FileIdentity
    public var trashIdentity: FileIdentity?
    public var trashFingerprint: String?
    public var status: ActivityStatus
    public var message: String?
    /// Optional for backward-compatible recovery of receipts created before nested units.
    public var originalParentIdentity: FileIdentity? = nil
    /// Store receipts retain OS-granted access to the exact moved item, never
    /// broad access to the user's Trash. Older/direct receipts decode as nil.
    public var trashAccessBookmark: Data? = nil
}

public struct ActivityReceipt: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public var items: [ActivityItem]
    public var issues: [ScanIssue]
    public var trashedBytes: Int64 { items.filter { $0.status == .trashed }.reduce(0) { $0 + $1.byteCount } }
    public var trashedCount: Int { items.filter { $0.status == .trashed }.count }
    public var canRestore: Bool { items.contains { $0.status == .trashed } }
}

public struct RestoreReport: Codable, Equatable, Sendable {
    public let receipt: ActivityReceipt
    public let restoredCount: Int
    public let issues: [ScanIssue]
}

public enum CacheScope: Sendable {
    case children
    case singleFile
}

public enum CacheCleanupPolicy: Sendable {
    case allowed
    case inspectOnly(String)
}

public enum CacheChildNameRule: Sendable {
    case karmaWebpack

    func matches(_ name: String) -> Bool {
        let prefix = "_karma_webpack_"
        guard name.hasPrefix(prefix) else { return false }
        let suffix = name.dropFirst(prefix.count)
        return (1...6).contains(suffix.count) && suffix.allSatisfy { $0 >= "0" && $0 <= "9" }
    }
}

public struct CacheRoot: Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let category: String
    public let url: URL
    public let consequence: String
    public let minimumAge: TimeInterval
    /// Lowercase executable names. Matching occurs against `ps` executable names only.
    public let guardedProcesses: [String]
    public let scope: CacheScope
    public let cleanupPolicy: CacheCleanupPolicy
    /// Completed immutable content must pass this additional byte-level rule.
    public let contentValidation: CacheContentValidation?
    /// Maximum nested cleanup-unit depth, used only for known independent caches.
    public let candidateDepth: Int
    /// Inventory omits these known or protected subtrees to avoid counting them twice.
    public let excludedURLs: [URL]
    public let childNameRule: CacheChildNameRule?
    public let excludedChildNameRules: [CacheChildNameRule]
    public let inspectionNodeLimit: Int
    public let inspectionTimeLimit: TimeInterval

    public init(id: String, title: String, subtitle: String, symbol: String, category: String,
                url: URL, consequence: String, minimumAge: TimeInterval = 7 * 86_400,
                guardedProcesses: [String] = [], scope: CacheScope = .children,
                cleanupPolicy: CacheCleanupPolicy = .allowed, candidateDepth: Int = 1,
                excludedURLs: [URL] = [], childNameRule: CacheChildNameRule? = nil, excludedChildNameRules: [CacheChildNameRule] = [], inspectionNodeLimit: Int = 25_000,
                inspectionTimeLimit: TimeInterval = 2, contentValidation: CacheContentValidation? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.category = category
        self.url = url.roomLexicallyNormalized
        self.consequence = consequence
        self.minimumAge = minimumAge
        self.guardedProcesses = guardedProcesses.map { $0.lowercased() }
        self.scope = scope
        self.cleanupPolicy = cleanupPolicy
        self.contentValidation = contentValidation
        self.candidateDepth = min(6, max(1, candidateDepth))
        self.excludedURLs = excludedURLs.map(\.roomLexicallyNormalized)
        self.childNameRule = childNameRule
        self.excludedChildNameRules = excludedChildNameRules
        self.inspectionNodeLimit = max(1, inspectionNodeLimit)
        self.inspectionTimeLimit = max(0, inspectionTimeLimit)
    }
}

extension CacheRoot {
    /// Classification is restricted to explicit rebuildable locations, never an
    /// inspect-only discovery parent or a sibling outside a named cache family.
    func allowsKnownLocation(_ url: URL) -> Bool {
        guard case .allowed = cleanupPolicy else { return false }
        if contentValidation == .npmSHA512 { return NPMContentPolicy.expectedDigest(originalURL: url, root: self) != nil }
        if scope == .singleFile { return url.path == self.url.path }
        let prefix = self.url.path + "/"
        if let childNameRule {
            guard url.path.hasPrefix(prefix), let first = url.path.dropFirst(prefix.count).split(separator: "/").first else { return false }
            return childNameRule.matches(String(first))
        }
        return url.path == self.url.path || url.path.hasPrefix(prefix)
    }
}

public struct ProtectedLocation: Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let reason: String

    public init(id: String, title: String, url: URL, reason: String) {
        self.id = id
        self.title = title
        self.url = url.roomLexicallyNormalized
        self.reason = reason
    }
}

public struct CacheConfiguration: Sendable {
    public let roots: [CacheRoot]
    public let protectedLocations: [ProtectedLocation]
    public let homeDirectory: URL
    public let inspectionIssues: [ScanIssue]
    /// nil preserves the direct edition's implicit catalogue. Store catalogues
    /// use an explicit (possibly empty) list, including for volume metadata.
    public let readAccessRoots: [URL]?

    public init(roots: [CacheRoot], protectedLocations: [ProtectedLocation] = [],
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                inspectionIssues: [ScanIssue] = [], readAccessRoots: [URL]? = nil) {
        self.roots = roots
        self.protectedLocations = protectedLocations
        self.homeDirectory = homeDirectory.roomLexicallyNormalized
        self.inspectionIssues = inspectionIssues
        self.readAccessRoots = readAccessRoots?.map(\.roomLexicallyNormalized)
    }
}

extension URL {
    /// Foundation's standardizedFileURL may rewrite /private/tmp to the /tmp
    /// symlink alias on macOS. Normalize dot components without resolving links.
    var roomLexicallyNormalized: URL {
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(String(component))
            }
        }
        return URL(fileURLWithPath: "/" + components.joined(separator: "/"), isDirectory: hasDirectoryPath)
    }
}
