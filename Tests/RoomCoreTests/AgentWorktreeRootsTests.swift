import Foundation
import Testing
@testable import RoomCore

@Suite("Agent worktree roots and owners")
struct AgentWorktreeRootsTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    @Test("Default roots are the Codex and Claude worktree folders in home")
    func defaults() {
        let roots = AgentWorkEngine.agentWorktreeRoots(home: home, environment: [:])
        #expect(roots.map(\.0.path) == ["/Users/someone/.codex/worktrees", "/Users/someone/.claude/worktrees"])
        #expect(roots.map(\.1) == [.codex, .claude])
    }

    @Test("CODEX_HOME and CLAUDE_CONFIG_DIR add worktree roots only strictly inside home")
    func overrides() {
        let roots = AgentWorkEngine.agentWorktreeRoots(home: home, environment: [
            "CODEX_HOME": "/Users/someone/agents/codex", "CLAUDE_CONFIG_DIR": "/Users/someone/agents/claude"])
        #expect(roots.contains { $0.0.path == "/Users/someone/agents/codex/worktrees" && $0.1 == .codex })
        #expect(roots.contains { $0.0.path == "/Users/someone/agents/claude/worktrees" && $0.1 == .claude })
        for value in ["/private/tmp/codex", "/Users/someone", "/Users/someone/../other", "relative/codex", "/Users/someone/./codex"] {
            #expect(AgentWorkEngine.agentWorktreeRoots(home: home, environment: ["CODEX_HOME": value]).count == 2, "\(value)")
        }
        // The documented default spelled out does not duplicate a root.
        #expect(AgentWorkEngine.agentWorktreeRoots(home: home, environment: ["CODEX_HOME": "/Users/someone/.codex"]).count == 2)
    }

    @Test("Approved-repository worktrees are attributed by folder, never guessed from names")
    func owners() {
        let roots = AgentWorkEngine.agentWorktreeRoots(home: home, environment: ["CODEX_HOME": "/Users/someone/agents/codex"])
        #expect(AgentWorkEngine.owner(of: "/Users/someone/.codex/worktrees/a1/repo", roots: roots) == .codex)
        #expect(AgentWorkEngine.owner(of: "/Users/someone/agents/codex/worktrees/a1/repo", roots: roots) == .codex)
        #expect(AgentWorkEngine.owner(of: "/Users/someone/Code/app/.claude/worktrees/fix", roots: roots) == .claude)
        #expect(AgentWorkEngine.owner(of: "/Users/someone/Code/app-feature", roots: roots) == .project)
        #expect(AgentWorkEngine.owner(of: "/Users/someone/.codex/worktrees-old/repo", roots: roots) == .project)
    }
}
