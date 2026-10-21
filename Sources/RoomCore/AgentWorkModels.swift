import Foundation

public enum AgentWorkOwner: String, Codable, Sendable { case codex, claude, project }
public enum AgentWorkPushState: String, Codable, Sendable { case notChecked, verified, unavailable, mismatch }
public struct AgentWorkPushVerification: Codable, Equatable, Sendable {
    public let state: AgentWorkPushState
    public let checkedAt: Date?
    public let head: String?
    public let remoteName: String?
    public let detail: String
    public var remoteRef: String? = nil
    public var localRemoteURL: URL? = nil
    public var localRemoteIdentity: FileIdentity? = nil
    public static let notChecked = Self(state: .notChecked, checkedAt: nil, head: nil, remoteName: nil,
        detail: "Verify the remote explicitly. Local tracking references are not proof that work was pushed.")
}
public struct AgentWorkItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let url: URL
    public let title: String
    public let owner: AgentWorkOwner
    public let repositoryURL: URL?
    public let gitAdminURL: URL?
    public let gitCommonURL: URL?
    public let branch: String?
    public let head: String?
    public let lastActivityAt: Date?
    public let allocatedBytes: Int64
    public let isPartial: Bool
    public let changedCount: Int
    public let untrackedCount: Int
    public let ignoredCount: Int
    public let processIDs: [Int32]
    public let isLinkedWorktree: Bool
    public let isLocked: Bool
    public let isPrunable: Bool
    public var heldReasons: [String]
    public var pushVerification: AgentWorkPushVerification
    public var canReviewForCleanup: Bool { heldReasons.isEmpty && pushVerification.state == .verified }
}
public struct AgentWorkProcessAssociation: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(processID):\(worktreeID)" }
    public let processID: Int32
    public let processName: String
    public let worktreeID: String
    public let detail: String
}
public struct AgentWorkReport: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let scannedAt: Date
    public var items: [AgentWorkItem]
    public let processAssociations: [AgentWorkProcessAssociation]
    public let issues: [ScanIssue]
    public let cancelled: Bool
    public let isPartial: Bool
}
public struct AgentWorkProgress: Sendable {
    public let inspectedCount: Int
    public let currentPath: String
}
public enum AgentWorkReceiptStatus: String, Codable, Sendable { case pending, trashed, restored, failed, needsAttention }
public struct AgentWorkReceipt: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let worktreeID: String
    public let originalURL: URL
    public let repositoryURL: URL
    public var trashURL: URL?
    public var status: AgentWorkReceiptStatus
    public var detail: String
    public let lockReason: String
    public let originalIdentity: FileIdentity
    public let parentIdentity: FileIdentity
    public let adminURL: URL
    public let adminIdentity: FileIdentity
    public let fingerprint: String
    public let head: String
    public let branch: String?
    public let dotGitPointer: String
    public let pushVerification: AgentWorkPushVerification
    public let commonURL: URL
    public let commonIdentity: FileIdentity
    public let dotGitIdentity: FileIdentity
    public var lockAcquired: Bool
    public var trashIdentity: FileIdentity?
}
