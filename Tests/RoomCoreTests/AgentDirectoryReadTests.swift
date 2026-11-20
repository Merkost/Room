import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Checked agent directory reads", .serialized)
struct AgentDirectoryReadTests {
    @Test("A real worktree directory read error retains a held partial row and cannot authorize cleanup")
    func worktreeReadErrorStaysHeld() async throws {
        let fixture = try await DirectoryReadFixture()
        defer { fixture.remove() }
        let failure = try FailingDirectoryRead(target: fixture.worktree)
        let engine = fixture.engine(reader: failure.reader)
        let contents = try Data(contentsOf: fixture.worktree.appendingPathComponent("tracked.txt"))
        let report = await engine.scan(approvedProjectRoots: [fixture.project])
        let item = try #require(report.items.first { $0.url.path == fixture.worktree.path })
        #expect(failure.didFailAfterRealEntry)
        #expect(report.isPartial && item.isPartial && !report.cancelled)
        #expect(item.heldReasons.contains { $0.contains("File inspection is incomplete") })
        await #expect(throws: (any Error).self) { try await engine.authorizationLocations(worktreeID: item.id) }
        await #expect(throws: (any Error).self) { try await engine.clean(worktreeID: item.id, confirmsFinished: true) }
        #expect(try Data(contentsOf: fixture.worktree.appendingPathComponent("tracked.txt")) == contents)
        #expect(await engine.history().isEmpty)

        // The error applies to one real stream read. A fresh complete scan can
        // measure the same unchanged worktree again without retaining the hold.
        let retry = await engine.scan(approvedProjectRoots: [fixture.project])
        let current = try #require(retry.items.first { $0.id == item.id })
        #expect(!current.isPartial)
        #expect(!current.heldReasons.contains { $0.contains("File inspection is incomplete") })
        #expect(try Data(contentsOf: fixture.worktree.appendingPathComponent("tracked.txt")) == contents)
    }

    @Test("Automatic discovery reports a directory IO error instead of claiming a complete empty inventory")
    func discoveryReadErrorIsReported() async throws {
        let fixture = try await DirectoryReadFixture()
        defer { fixture.remove() }
        let failure = try FailingDirectoryRead(target: fixture.discoveryRoot)
        let report = await fixture.engine(reader: failure.reader).scan()
        #expect(failure.didFailAfterRealEntry)
        #expect(report.isPartial && !report.cancelled)
        #expect(report.issues.contains { $0.url.path == fixture.discoveryRoot.path && $0.message.contains("could not be completely read") })
        #expect(FileManager.default.fileExists(atPath: fixture.worktree.appendingPathComponent("tracked.txt").path))
    }

    @Test("Ordinary EOF is complete even when unrelated metadata work left errno set")
    func staleErrnoDoesNotBecomeAReadError() throws {
        let root = URL(fileURLWithPath: "/private/tmp/Room-AgentEOF-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("owned".utf8).write(to: root.appendingPathComponent("file"))
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        #expect(fd >= 0)
        guard fd >= 0 else { return }
        guard let stream = fdopendir(fd) else { close(fd); Issue.record("Owned directory stream could not open"); return }
        defer { closedir(stream) }
        let reader = AgentDirectoryReader()
        var names: Set<String> = []
        while true {
            errno = EIO
            guard let name = try reader.nextName(in: stream) else { break }
            if name != "." && name != ".." { names.insert(name) }
        }
        #expect(names == ["file"])
    }
}

private struct FailingDirectoryRead: Sendable {
    private final class Counter: Sendable {
        struct State: Sendable { var realEntries = 0; var failed = false }
        let value = Mutex(State())
    }
    private let state: Counter
    let reader: AgentDirectoryReader
    var didFailAfterRealEntry: Bool { state.value.withLock { $0.failed && $0.realEntries > 0 } }

    init(target: URL) throws {
        var identity = stat()
        guard lstat(target.path, &identity) == 0 else { throw AgentWorkError.message("Owned target metadata unavailable") }
        let device = identity.st_dev, inode = identity.st_ino
        let state = Counter()
        self.state = state
        self.reader = AgentDirectoryReader { stream in
            var current = stat()
            guard fstat(dirfd(stream), &current) == 0, current.st_dev == device, current.st_ino == inode else { return readdir(stream) }
            let shouldFail = state.value.withLock { value in
                guard !value.failed && value.realEntries > 0 else { return false }
                value.failed = true
                return true
            }
            if shouldFail { errno = EIO; return nil }
            let entry = readdir(stream)
            if let entry {
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name != "." && name != ".." { state.value.withLock { $0.realEntries += 1 } }
            }
            return entry
        }
    }
}

private struct DirectoryReadFixture: Sendable {
    let home: URL
    let project: URL
    let worktree: URL
    let discoveryRoot: URL
    let activity: URL
    let trash: URL
    let future: Date

    init() async throws {
        home = URL(fileURLWithPath: "/private/tmp/Room-AgentDirectory-" + UUID().uuidString, isDirectory: true)
        project = home.appendingPathComponent("project", isDirectory: true)
        discoveryRoot = home.appendingPathComponent(".codex/worktrees", isDirectory: true)
        worktree = discoveryRoot.appendingPathComponent("owned", isDirectory: true)
        activity = home.appendingPathComponent("receipts", isDirectory: true)
        trash = home.appendingPathComponent("fixture-trash", isDirectory: true)
        future = Date().addingTimeInterval(30 * 86_400)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: discoveryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        try await git(["init", "--initial-branch=main"], at: project)
        try await git(["config", "user.name", "Fixture"], at: project)
        try await git(["config", "user.email", "fixture@example.invalid"], at: project)
        try Data("owned tracked data\n".utf8).write(to: project.appendingPathComponent("tracked.txt"))
        try await git(["add", "tracked.txt"], at: project)
        try await git(["commit", "-m", "Owned directory fixture"], at: project)
        try await git(["worktree", "add", "-b", "owned-work", worktree.path], at: project)
    }

    private func git(_ arguments: [String], at url: URL) async throws {
        let result = try await AgentCommand.run(URL(fileURLWithPath: "/usr/bin/git"), AgentGit.options + arguments, url, 5)
        guard result.status == 0 else { throw AgentWorkError.message("Owned Git setup failed") }
    }

    func engine(reader: AgentDirectoryReader) -> AgentWorkEngine {
        AgentWorkEngine(home: home, activity: activity, fixtureTrash: trash, clock: { future }, directoryReader: reader)
    }

    func remove() { try? FileManager.default.removeItem(at: home) }
}
