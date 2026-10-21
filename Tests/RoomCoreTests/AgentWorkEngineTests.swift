import CryptoKit
import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Agent worktree review and reversible cleanup", .serialized)
struct AgentWorkEngineTests {
    @Test("Read-only scans report exact clean linked work and never trust cached remote tracking refs")
    func reviewAndLiveProof() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        #expect(item.isLinkedWorktree)
        #expect(item.branch == "agent-work")
        #expect(item.changedCount == 0 && item.untrackedCount == 0 && item.ignoredCount == 0)
        #expect(item.heldReasons.isEmpty, "\(item.heldReasons)")
        #expect(item.pushVerification.state == .notChecked)
        #expect(!item.canReviewForCleanup)
        let proof = await engine.verifyRemote(worktreeID: item.id)
        #expect(proof.state == .verified, "\(proof.detail)")
        #expect(proof.remoteName?.hasPrefix("Local remote") == true)
        #expect(try await engine.authorizationLocations(worktreeID: item.id).count == 2)
        _ = try await fixture.git(["--git-dir=" + fixture.remote.path, "update-ref", "-d", "refs/heads/agent-work"], at: fixture.home)
        let stale = await engine.verifyRemote(worktreeID: item.id)
        #expect(stale.state == .mismatch)
    }

    @Test("Owned linked work round-trips through Trash and restart without deleting branch or registry")
    func trashRestoreRoundTrip() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        let receipt = try await engine.clean(worktreeID: item.id, confirmsFinished: true)
        #expect(receipt.status == .trashed)
        #expect(receipt.lockAcquired)
        #expect(!FileManager.default.fileExists(atPath: fixture.worktree.path))
        #expect(FileManager.default.fileExists(atPath: receipt.adminURL.appendingPathComponent("HEAD").path))
        let branch = try await fixture.git(["show-ref", "--verify", "refs/heads/agent-work"], at: fixture.project)
        #expect(branch.status == 0)
        let restored = try await fixture.engine().restore(receiptID: receipt.id)
        #expect(restored.status == .restored)
        #expect(!restored.lockAcquired)
        #expect(FileManager.default.fileExists(atPath: fixture.worktree.appendingPathComponent("tracked.txt").path))
        #expect(!FileManager.default.fileExists(atPath: receipt.adminURL.appendingPathComponent("locked").path))
    }

    @Test("Dirty, untracked, ignored, skipped index paths and in-progress Git operations remain held")
    func localResourcesHeld() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        try Data("changed".utf8).write(to: fixture.worktree.appendingPathComponent("tracked.txt"))
        try Data("untracked".utf8).write(to: fixture.worktree.appendingPathComponent("notes.txt"))
        try Data("ignored".utf8).write(to: fixture.worktree.appendingPathComponent("local.bin"))
        let report = await fixture.engine().scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        #expect(item.changedCount == 1 && item.untrackedCount == 1 && item.ignoredCount == 1)
        #expect(!item.heldReasons.isEmpty)
        _ = try await fixture.git(["update-index", "--assume-unchanged", "tracked.txt"], at: fixture.worktree)
        let second = await fixture.engine().scan(approvedProjectRoots: [fixture.project])
        #expect(second.items.first { $0.id == item.id }?.heldReasons.contains { $0.contains("index hides") } == true)
    }

    @Test("Process path association uses component boundaries and incomplete activity always holds")
    func activityBoundaries() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let active = fixture.engine(processes: { AgentProcessSnapshot(paths: [
            AgentProcessPath(pid: 101, name: "node", url: fixture.worktree.appendingPathComponent("tracked.txt")),
            AgentProcessPath(pid: 102, name: "node", url: URL(fileURLWithPath: fixture.worktree.path + "-other/file"))
        ], complete: true) })
        let report = await active.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        #expect(item.processIDs == [101])
        #expect(report.processAssociations.contains { $0.processID == 101 && $0.worktreeID == item.id })
        #expect(!report.processAssociations.contains { $0.processID == 102 })
        let unknown = fixture.engine(processes: { AgentProcessSnapshot(paths: [], complete: false) })
        let partial = await unknown.scan(approvedProjectRoots: [fixture.project])
        #expect(partial.items.first { $0.id == item.id }?.heldReasons.contains { $0.contains("could not be checked") } == true)
    }

    @Test("Untrusted executable configuration is held without executing its marker commands")
    func executableConfigurationHeld() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let marker = fixture.home.appendingPathComponent("must-not-exist")
        _ = try await fixture.git(["config", "filter.hostile.clean", "touch " + marker.path], at: fixture.project)
        _ = try await fixture.git(["config", "filter.hostile.process", "touch " + marker.path], at: fixture.project)
        _ = try await fixture.git(["config", "core.fsmonitor", "touch " + marker.path], at: fixture.project)
        _ = try await fixture.git(["config", "core.sshCommand", "touch " + marker.path], at: fixture.project)
        let report = await fixture.engine().scan(approvedProjectRoots: [fixture.project])
        #expect(report.items.first { $0.url.path == fixture.worktree.path }?.canReviewForCleanup == false)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("Restore never overwrites new work or follows a replaced parent")
    func restoreCollisionAndSymlink() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        let receipt = try await engine.clean(worktreeID: item.id, confirmsFinished: true)
        try FileManager.default.createDirectory(at: fixture.worktree, withIntermediateDirectories: false)
        try Data("new work".utf8).write(to: fixture.worktree.appendingPathComponent("new.txt"))
        await #expect(throws: (any Error).self) { try await engine.restore(receiptID: receipt.id) }
        #expect(FileManager.default.fileExists(atPath: fixture.worktree.appendingPathComponent("new.txt").path))
        #expect(FileManager.default.fileExists(atPath: receipt.trashURL!.path))
        #expect(FileManager.default.fileExists(atPath: receipt.adminURL.appendingPathComponent("locked").path))
    }

    @Test("Changed remote state, missing attestation and preexisting Git lock cannot authorize Trash")
    func cleanupGates() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        await #expect(throws: (any Error).self) { try await engine.clean(worktreeID: item.id, confirmsFinished: false) }
        _ = try await fixture.git(["worktree", "lock", "--reason", "User lock", fixture.worktree.path], at: fixture.project)
        let locked = await fixture.engine().scan(approvedProjectRoots: [fixture.project])
        #expect(locked.items.first { $0.id == item.id }?.isLocked == true)
        #expect(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    @Test("Worktree-local configuration, includes and redirected trees are held before filters can execute")
    func worktreeConfigurationHeld() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let marker = fixture.home.appendingPathComponent("filter-marker")
        _ = try await fixture.git(["config", "extensions.worktreeConfig", "true"], at: fixture.project)
        _ = try await fixture.git(["config", "--worktree", "filter.hostile.clean", "touch " + marker.path], at: fixture.worktree)
        try Data("tracked.txt filter=hostile\n".utf8).write(to: fixture.worktree.appendingPathComponent(".gitattributes"))
        let report = await fixture.engine().scan(approvedProjectRoots: [fixture.project])
        #expect(report.items.first { $0.url.path == fixture.worktree.path }?.canReviewForCleanup == false)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("A lock created just before a command error is discovered and safely rolled back")
    func interruptedLockAcquisition() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let runner: @Sendable (URL, [String], URL?, TimeInterval) async throws -> AgentCommandResult = { executable, arguments, cwd, timeout in
            let result = try await AgentCommand.run(executable, arguments, cwd, timeout)
            if arguments.contains("lock"), result.status == 0 { throw CancellationError() }
            return result
        }
        let engine = AgentWorkEngine(home: fixture.home, activity: fixture.activity, fixtureTrash: fixture.trash,
            clock: { fixture.future }, runner: runner)
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        await #expect(throws: (any Error).self) { try await engine.clean(worktreeID: item.id, confirmsFinished: true) }
        let history = await engine.history()
        #expect(history.first?.status == .failed)
        #expect(history.first?.lockAcquired == false)
        #expect(FileManager.default.fileExists(atPath: fixture.worktree.path))
        #expect(!FileManager.default.fileExists(atPath: item.gitAdminURL!.appendingPathComponent("locked").path))
    }

    @Test("A changed owned recovery lock is never unlocked by Undo")
    func changedLockHeld() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        let receipt = try await engine.clean(worktreeID: item.id, confirmsFinished: true)
        let lock = receipt.adminURL.appendingPathComponent("locked")
        try Data("User replaced this lock\n".utf8).write(to: lock)
        await #expect(throws: (any Error).self) { try await engine.restore(receiptID: receipt.id) }
        #expect(String(decoding: try Data(contentsOf: lock), as: UTF8.self).contains("User replaced"))
        #expect(!FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    @Test("lsof access errors and stderr never count as complete activity evidence")
    func incompleteProcessEvidence() {
        let normal = Data("p101\0cnode\0fcwd\0n/private/tmp/project\0".utf8)
        #expect(AgentProcesses.parse(AgentCommandResult(status: 0, data: normal)).complete)
        #expect(!AgentProcesses.parse(AgentCommandResult(status: 0, data: normal, stderr: Data("warning".utf8))).complete)
        let denied = normal + Data("n/Users/example (CWD info error: Operation not permitted)\0".utf8)
        #expect(!AgentProcesses.parse(AgentCommandResult(status: 0, data: denied)).complete)
        #expect(AgentProcesses.observedPIDs(normal) == [101])
    }

    @Test("A detached linked HEAD with exact live remote proof remains recoverable")
    func detachedLinkedWork() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        _ = try await fixture.git(["checkout", "--detach"], at: fixture.worktree)
        let engine = fixture.engine()
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        #expect(item.branch == nil)
        #expect(item.heldReasons.isEmpty)
        let receipt = try await engine.clean(worktreeID: item.id, confirmsFinished: true)
        #expect(receipt.branch == nil && receipt.status == .trashed)
        #expect(try await fixture.engine().restore(receiptID: receipt.id).status == .restored)
    }

    @Test("Real macOS Trash roundtrip preserves detached HEAD, owned lock and exact file bytes")
    func systemTrashRoundTrip() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        _ = try await fixture.git(["checkout", "--detach"], at: fixture.worktree)
        let file = fixture.worktree.appendingPathComponent("tracked.txt")
        let before = SHA256.hash(data: try Data(contentsOf: file))
        let engine = AgentWorkEngine(home: fixture.home, activity: fixture.activity, fixtureTrash: nil, clock: { fixture.future })
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        #expect(item.heldReasons.isEmpty)
        let receipt = try await engine.clean(worktreeID: item.id, confirmsFinished: true)
        let trashURL = try #require(receipt.trashURL)
        // This cleanup targets only this test's exact returned Trash item if Undo fails.
        defer { if FileManager.default.fileExists(atPath: trashURL.path) { try? FileManager.default.removeItem(at: trashURL) } }
        #expect(receipt.status == .trashed && receipt.lockAcquired)
        #expect(FileManager.default.fileExists(atPath: receipt.adminURL.appendingPathComponent("locked").path))
        let restart = AgentWorkEngine(home: fixture.home, activity: fixture.activity, fixtureTrash: nil, clock: { fixture.future })
        let restored = try await restart.restore(receiptID: receipt.id)
        #expect(restored.status == .restored && !restored.lockAcquired)
        #expect(SHA256.hash(data: try Data(contentsOf: file)) == before)
        let head = try await fixture.git(["rev-parse", "HEAD"], at: fixture.worktree)
        #expect(head.text.trimmingCharacters(in: .whitespacesAndNewlines) == receipt.head)
    }

    @Test("Cancelling an in-flight scan never publishes cleanup candidates")
    func cancellationRevokesCandidates() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let reached = Mutex(false)
        let runner: @Sendable (URL, [String], URL?, TimeInterval) async throws -> AgentCommandResult = { executable, arguments, cwd, timeout in
            if arguments.contains("status") { reached.withLock { $0 = true }; try await Task.sleep(for: .seconds(5)) }
            return try await AgentCommand.run(executable, arguments, cwd, timeout)
        }
        let engine = AgentWorkEngine(home: fixture.home, activity: fixture.activity, fixtureTrash: fixture.trash,
            clock: { fixture.future }, runner: runner)
        let scan = Task { await engine.scan(approvedProjectRoots: [fixture.project]) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !reached.withLock({ $0 }), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(reached.withLock { $0 })
        scan.cancel()
        #expect(await scan.value.cancelled)
        #expect(await engine.verifyRemote(worktreeID: fixture.worktree.path).state == .notChecked)
        #expect(await engine.history().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    @Test("A cancelled older scan cannot erase a newer completed scan's verification candidates")
    func overlappingScanGeneration() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let firstStatus = Mutex(true)
        let reached = Mutex(false)
        let runner: @Sendable (URL, [String], URL?, TimeInterval) async throws -> AgentCommandResult = { executable, arguments, cwd, timeout in
            let delay = arguments.contains("status") && firstStatus.withLock { value in let result = value; value = false; return result }
            if delay { reached.withLock { $0 = true }; try await Task.sleep(for: .seconds(5)) }
            return try await AgentCommand.run(executable, arguments, cwd, timeout)
        }
        let engine = AgentWorkEngine(home: fixture.home, activity: fixture.activity, fixtureTrash: fixture.trash,
            clock: { fixture.future }, runner: runner)
        let older = Task { await engine.scan(approvedProjectRoots: [fixture.project]) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !reached.withLock({ $0 }), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let current = await engine.scan(approvedProjectRoots: [fixture.project])
        #expect(!current.cancelled)
        older.cancel()
        #expect(await older.value.cancelled)
        #expect(await engine.verifyRemote(worktreeID: fixture.worktree.path).state == .verified)
    }

    @Test("Project-local Claude worktrees retain the conservative Node-owner hold")
    func projectClaudeOwner() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        let parent = fixture.project.appendingPathComponent(".claude/worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let destination = parent.appendingPathComponent("agent-task", isDirectory: true)
        _ = try await fixture.git(["worktree", "move", fixture.worktree.path, destination.path], at: fixture.project)
        let engine = fixture.engine(processes: { AgentProcessSnapshot(paths: [
            AgentProcessPath(pid: 505, name: "node", url: URL(fileURLWithPath: "/private/tmp/other-agent/runtime"))
        ], complete: true) })
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == destination.path })
        #expect(item.owner == .claude)
        #expect(item.heldReasons.contains { $0.contains("owning agent is running") })
    }

    @Test("External large-file payload stores are held despite an otherwise clean Git tree")
    func largeFilePayloadHeld() async throws {
        let fixture = try await AgentFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.project.appendingPathComponent(".git/lfs"), withIntermediateDirectories: true)
        let report = await fixture.engine().scan(approvedProjectRoots: [fixture.project])
        #expect(report.items.first { $0.url.path == fixture.worktree.path }?.heldReasons.contains { $0.contains("payloads need separate backup") } == true)
    }

    @Test("Remote parser rejects helpers, credentials, rewriting syntax and prefix impostors")
    func remoteValidation() {
        #expect(AgentGit.allowedRemote("https://github.com/example/project.git"))
        #expect(AgentGit.allowedRemote("git@github.com:example/project.git"))
        for value in ["ext::touch /tmp/marker", "https://token@github.com/repo", "ssh://-oProxyCommand=x/repo", "git@-host:repo", "file:///tmp/repo", "../repo", "https://example.com/repo?token=x"] {
            #expect(!AgentGit.allowedRemote(value), "\(value)")
        }
        let head = String(repeating: "a", count: 40)
        #expect(!AgentGit.remoteContainsExact(head: head, data: Data((head + "\trefs/not-branches/main\n").utf8)))
        #expect(AgentGit.remoteContainsExact(head: head, data: Data((head + "\trefs/heads/main\n").utf8)))
    }
}

private struct AgentFixture: Sendable {
    let home: URL
    let project: URL
    let worktree: URL
    let remote: URL
    let activity: URL
    let trash: URL
    let future: Date
    init() async throws {
        home = URL(fileURLWithPath: "/private/tmp/RoomAgent-" + UUID().uuidString, isDirectory: true)
        project = home.appendingPathComponent("project", isDirectory: true)
        worktree = home.appendingPathComponent("agent-work", isDirectory: true)
        remote = home.appendingPathComponent("backup.git", isDirectory: true)
        activity = home.appendingPathComponent("receipts", isDirectory: true)
        trash = home.appendingPathComponent("fixture-trash", isDirectory: true)
        future = Date().addingTimeInterval(30 * 86_400)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        _ = try await git(["init", "--initial-branch=main"], at: project)
        _ = try await git(["config", "user.name", "Fixture"], at: project)
        _ = try await git(["config", "user.email", "fixture@example.invalid"], at: project)
        try Data("tracked\n".utf8).write(to: project.appendingPathComponent("tracked.txt"))
        try Data("local.bin\n".utf8).write(to: project.appendingPathComponent(".gitignore"))
        _ = try await git(["add", "tracked.txt", ".gitignore"], at: project)
        _ = try await git(["commit", "-m", "Fixture"], at: project)
        _ = try await git(["worktree", "add", "-b", "agent-work", worktree.path], at: project)
        _ = try await git(["init", "--bare", remote.path], at: home)
        _ = try await git(["remote", "add", "origin", remote.path], at: project)
        _ = try await git(["-c", "protocol.file.allow=always", "push", "origin", "agent-work"], at: project)
    }
    func git(_ arguments: [String], at cwd: URL) async throws -> AgentCommandResult {
        let result = try await AgentCommand.run(URL(fileURLWithPath: "/usr/bin/git"), AgentGit.options + arguments, cwd, 5)
        guard result.status == 0 else { throw AgentWorkError.message("Fixture Git failed: " + arguments.joined(separator: " ")) }
        return result
    }
    func engine(processes: @escaping @Sendable () async throws -> AgentProcessSnapshot = { AgentProcessSnapshot(paths: [], complete: true) }) -> AgentWorkEngine {
        AgentWorkEngine(home: home, activity: activity, fixtureTrash: trash, clock: { future }, processes: processes)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
