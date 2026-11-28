import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@MainActor
struct RoomAgentWorktreeHintTests {
    @Test func thresholdIsFiveGigabytes() {
        #expect(RoomAgentWorktreeHint.heavyBytes == 5_000_000_000)
        #expect(RoomAgentWorktreeHint.suggestedBytes(scanned: nil, measured: 4_999_999_999) == nil)
        #expect(RoomAgentWorktreeHint.suggestedBytes(scanned: nil, measured: 5_000_000_000) == 5_000_000_000)
    }

    @Test func scanWinsOverCachesMeasurement() {
        #expect(RoomAgentWorktreeHint.suggestedBytes(scanned: 1_000, measured: 12_000_000_000) == nil)
        #expect(RoomAgentWorktreeHint.suggestedBytes(scanned: 12_000_000_000, measured: 0) == 12_000_000_000)
    }

    @Test func cachesMeasurementCountsOnlyAgentWorktreeFolders() {
        let bytes = RoomAgentWorktreeHint.measuredBytes([("codex-worktrees", 3_000_000_000), ("claude-worktrees", 4_000_000_000),
            ("claude-projects", 9_000_000_000)])
        #expect(bytes == 7_000_000_000)
    }

    @Test func scanCountsAgentWorktreesOnly() {
        func item(_ owner: AgentWorkOwner, _ bytes: Int64) -> AgentWorkItem {
            AgentWorkItem(id: UUID().uuidString, url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)"), title: "w", owner: owner,
                repositoryURL: nil, gitAdminURL: nil, gitCommonURL: nil, branch: nil, head: nil, lastActivityAt: nil,
                allocatedBytes: bytes, isPartial: false, changedCount: 0, untrackedCount: 0, ignoredCount: 0, processIDs: [],
                isLinkedWorktree: true, isLocked: false, isPrunable: false, heldReasons: [], pushVerification: .notChecked)
        }
        let report = AgentWorkReport(id: UUID(), scannedAt: .now, items: [item(.codex, 2), item(.claude, 3), item(.project, 100)],
            processAssociations: [], issues: [], cancelled: false, isPartial: false)
        #expect(RoomAgentWorktreeHint.scannedBytes(report) == 5)
        #expect(RoomAgentWorktreeHint.scannedBytes(nil) == nil)
    }

    @Test func copyIsOneLineAndHideMasksTheSize() {
        let line = RoomAgentWorktreeHint.line(bytes: 12_000_000_000, hidden: false)
        #expect(line.hasPrefix("Agent worktrees take 12"))
        #expect(line.hasSuffix("Review them in Developer."))
        let hidden = RoomAgentWorktreeHint.line(bytes: 12_000_000_000, hidden: true)
        #expect(!hidden.contains { $0.isNumber })
        #expect(RoomAgentWorktreeHint.actionTitle == "Review in Developer")
    }
}
