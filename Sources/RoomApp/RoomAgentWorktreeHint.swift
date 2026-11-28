import Foundation
import RoomCore

/// One quiet line on Caches when agent worktrees are heavy. Caches never cleans,
/// moves or prunes a worktree; the line only points at Developer > Worktrees.
enum RoomAgentWorktreeHint {
    /// 5 GB, decimal like every size Room shows.
    static let heavyBytes: Int64 = 5_000_000_000

    /// Measurements from the Caches check that count as agent worktrees.
    static let cacheMeasurementIDs: Set<String> = ["codex-worktrees", "claude-worktrees"]

    /// Agent-made worktrees from a Developer scan; worktrees the user made by hand are not counted.
    static func scannedBytes(_ report: AgentWorkReport?) -> Int64? {
        guard let report else { return nil }
        return report.items.filter { $0.owner != .project }.reduce(Int64(0)) { $0 + max(0, $1.allocatedBytes) }
    }

    /// Caches-check measurements of the known agent worktree folders.
    static func measuredBytes(_ measurements: [(id: String, bytes: Int64)]) -> Int64 {
        measurements.filter { cacheMeasurementIDs.contains($0.id) }.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
    }

    /// A Developer scan wins once it exists; until then the Caches check's measurement stands in.
    static func suggestedBytes(scanned: Int64?, measured: Int64) -> Int64? {
        let bytes = scanned ?? measured
        return bytes >= heavyBytes ? bytes : nil
    }

    static func line(bytes: Int64, hidden: Bool) -> String {
        "Agent worktrees take \(RoomCachesVisibility.figure(RoomFormat.gb(bytes), hidden: hidden)). Review them in Developer."
    }

    static let actionTitle = "Review in Developer"
}
