#if !ROOM_APP_STORE
import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Worktree verification availability", .serialized) @MainActor
struct AgentWorkVerificationTests {
    @Test("A stopped real scan retains inspection rows but cannot dispatch verification until a new scan completes")
    func stoppedScanRequiresRescan() async throws {
        let fixture = try await VerificationFixture()
        defer { fixture.remove() }
        let suite = "Room-AgentVerification-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = VerificationCommandGate(holdSecondStatus: true)
        let engine = fixture.engine(gate: gate)
        let model = AgentWorkModel(engine: engine, access: RoomFileAccess(defaults: defaults))
        model.scan()
        try await gate.waitUntilPaused()
        model.stop()
        await gate.release()
        try await waitUntil { !model.isScanning }

        let report = try #require(model.report)
        #expect(report.cancelled && report.isPartial)
        let item = try #require(report.items.first)
        #expect(item.head?.isEmpty == false)
        #expect(!model.canVerify(item))
        #expect(model.verificationUnavailableReason(for: item)?.contains("Rescan worktrees") == true)
        let commandsBefore = await gate.commandCount
        model.verify(item)
        #expect(model.verifyingID == nil)
        #expect(model.statusMessage?.contains("Rescan worktrees") == true)
        #expect(await gate.commandCount == commandsBefore)
        #expect(await gate.remoteCount == 0)
        // Core's cancelled-candidate boundary remains unchanged and rejects an
        // independent direct call too; the UI guard does not mint a candidate.
        #expect(await engine.verifyRemote(worktreeID: item.id).state == .notChecked)
        #expect(await gate.commandCount == commandsBefore)

        model.scan()
        try await waitUntil { !model.isScanning }
        let complete = try #require(model.report)
        #expect(!complete.cancelled)
        let current = try #require(complete.items.first { $0.id == item.id })
        #expect(model.canVerify(current))
        model.verify(current)
        #expect(model.verifyingID == current.id)
        try await waitUntil { model.verifyingID == nil }
        #expect(model.report?.items.first { $0.id == current.id }?.pushVerification.state == .verified)
        #expect(await gate.remoteCount > 0)
        #expect(try Data(contentsOf: fixture.first.appendingPathComponent("tracked.txt")) == fixture.contents)
        #expect(try Data(contentsOf: fixture.second.appendingPathComponent("tracked.txt")) == fixture.contents)
        #expect(await engine.history().isEmpty)
    }

    @Test("A complete report with an unrelated failed row still verifies its valid candidate")
    func unrelatedPartialReportDoesNotBlockVerification() async throws {
        let fixture = try await VerificationFixture()
        defer { fixture.remove() }
        let broken = fixture.first.deletingLastPathComponent().appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: false)
        try Data("gitdir: missing-owned-metadata\n".utf8).write(to: broken.appendingPathComponent(".git"))
        let suite = "Room-AgentPartialVerification-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = VerificationCommandGate(holdSecondStatus: false)
        let model = AgentWorkModel(engine: fixture.engine(gate: gate), access: RoomFileAccess(defaults: defaults))
        model.scan()
        try await waitUntil { !model.isScanning }

        let report = try #require(model.report)
        #expect(!report.cancelled && report.isPartial && !report.issues.isEmpty)
        let failed = try #require(report.items.first { $0.url.path == broken.path })
        #expect(failed.head == nil && !model.canVerify(failed))
        let commandsBefore = await gate.commandCount
        model.verify(failed)
        #expect(model.verifyingID == nil)
        #expect(model.statusMessage?.contains("commit could not be inspected") == true)
        #expect(await gate.commandCount == commandsBefore)
        let valid = try #require(report.items.first { $0.url.path == fixture.first.path })
        #expect(model.verificationUnavailableReason(for: valid) == nil)
        #expect(model.canVerify(valid))
        model.verify(valid)
        try await waitUntil { model.verifyingID == nil }
        #expect(model.report?.items.first { $0.id == valid.id }?.pushVerification.state == .verified)
        #expect(await gate.remoteCount > 0)
        #expect(try Data(contentsOf: fixture.first.appendingPathComponent("tracked.txt")) == fixture.contents)
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(predicate())
    }
}

private struct VerificationFixture: Sendable {
    let home: URL
    let project: URL
    let first: URL
    let second: URL
    let remote: URL
    let activity: URL
    let trash: URL
    let future: Date
    let contents = Data("owned tracked fixture\n".utf8)

    init() async throws {
        home = URL(fileURLWithPath: "/private/tmp/Room-AgentVerify-" + UUID().uuidString, isDirectory: true)
        project = home.appendingPathComponent("project", isDirectory: true)
        first = home.appendingPathComponent(".codex/worktrees/first", isDirectory: true)
        second = home.appendingPathComponent(".codex/worktrees/second", isDirectory: true)
        remote = home.appendingPathComponent("backup.git", isDirectory: true)
        activity = home.appendingPathComponent("receipts", isDirectory: true)
        trash = home.appendingPathComponent("fixture-trash", isDirectory: true)
        future = Date().addingTimeInterval(30 * 86_400)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        _ = try await git(["init", "--initial-branch=main"], at: project)
        _ = try await git(["config", "user.name", "Fixture"], at: project)
        _ = try await git(["config", "user.email", "fixture@example.invalid"], at: project)
        try contents.write(to: project.appendingPathComponent("tracked.txt"))
        _ = try await git(["add", "tracked.txt"], at: project)
        _ = try await git(["commit", "-m", "Fixture"], at: project)
        _ = try await git(["worktree", "add", "-b", "work-first", first.path], at: project)
        _ = try await git(["worktree", "add", "-b", "work-second", second.path], at: project)
        _ = try await git(["init", "--bare", remote.path], at: home)
        _ = try await git(["remote", "add", "origin", remote.path], at: project)
        _ = try await git(["-c", "protocol.file.allow=always", "push", "origin", "work-first", "work-second"], at: project)
    }

    private func git(_ arguments: [String], at cwd: URL) async throws -> AgentCommandResult {
        let result = try await AgentCommand.run(URL(fileURLWithPath: "/usr/bin/git"), AgentGit.options + arguments, cwd, 5)
        guard result.status == 0 else { throw AgentWorkError.message("Owned fixture Git setup failed.") }
        return result
    }

    func engine(gate: VerificationCommandGate) -> AgentWorkEngine {
        AgentWorkEngine(home: home, activity: activity, fixtureTrash: trash, clock: { future },
            runner: { executable, arguments, cwd, timeout in
                try await gate.beforeCommand(arguments)
                return try await AgentCommand.run(executable, arguments, cwd, timeout)
            })
    }

    func remove() { try? FileManager.default.removeItem(at: home) }
}

private actor VerificationCommandGate {
    let holdSecondStatus: Bool
    private(set) var commandCount = 0
    private(set) var remoteCount = 0
    private var statusCount = 0
    private var paused = false
    private var released = false
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init(holdSecondStatus: Bool) { self.holdSecondStatus = holdSecondStatus }

    func beforeCommand(_ arguments: [String]) async throws {
        commandCount += 1
        if arguments.contains("ls-remote") { remoteCount += 1 }
        guard arguments.contains("status") else { return }
        statusCount += 1
        guard holdSecondStatus && statusCount == 2 else { return }
        paused = true
        let awaiting = Array(waiters.values)
        waiters.removeAll()
        awaiting.forEach { $0.resume(returning: true) }
        await withCheckedContinuation { continuation in
            if released { continuation.resume() }
            else { pending = continuation }
        }
        try Task.checkCancellation()
    }

    func release() {
        released = true
        pending?.resume()
        pending = nil
    }

    func waitUntilPaused() async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    guard await self.arrival() else { throw CancellationError() }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw VerificationGateError.timedOut
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch {
            release()
            throw error
        }
    }

    private func arrival() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if paused { continuation.resume(returning: true) }
                else if Task.isCancelled { continuation.resume(returning: false) }
                else { waiters[id] = continuation }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(returning: false) }
}

private enum VerificationGateError: Error { case timedOut }
#endif
