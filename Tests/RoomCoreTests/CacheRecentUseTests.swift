import Foundation
import Synchronization
import Testing
@testable import RoomCore

/// Recently used caches may be ticked by hand; nothing else about what can move is relaxed.
@Suite("Recently used caches", .serialized)
struct CacheRecentUseTests {
    private let week: TimeInterval = 7 * 86_400

    @Test func aRecentCacheIsOfferedUntickedAndMovesOnlyWhenAskedFor() async throws {
        let fixture = try RecentFixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/fresh", "cached")
        let engine = fixture.engine(age: week, processes: ["owner"])
        let report = await engine.scan()
        let entry = try #require(report.groups.first?.entries.first)
        #expect(!entry.eligibility.isEligible && entry.eligibility.isRecent)
        #expect(report.eligibleEntries.isEmpty && report.eligibleBytes == 0)
        #expect(report.groups.first?.recentEntries.map(\.id) == [entry.id])

        let refused = await engine.clean(entryIDs: [entry.id])
        #expect(refused.trashedCount == 0, "a caller that did not opt in moves nothing")
        #expect(FileManager.default.fileExists(atPath: file.path))

        let moved = await engine.clean(entryIDs: [entry.id], includingRecent: [entry.id])
        #expect(moved.trashedCount == 1, "\(moved.issues)")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aRunningOwnerHoldsEvenARecentCache() async throws {
        let fixture = try RecentFixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/fresh", "cached")
        let engine = fixture.engine(age: week, processes: ["owner"], running: ["owner"])
        let entry = try #require(await engine.scan().groups.first?.entries.first)
        #expect(entry.eligibility.isInUse && !entry.eligibility.isSelectable)
        let receipt = await engine.clean(entryIDs: [entry.id], includingRecent: [entry.id])
        #expect(receipt.trashedCount == 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func anOwnerStartingAfterTheCheckStopsTheMove() async throws {
        let fixture = try RecentFixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/fresh", "cached")
        let running = RunningNames()
        let engine = fixture.engine(age: week, processes: ["owner"], running: running)
        let entry = try #require(await engine.scan().groups.first?.entries.first)
        try #require(entry.eligibility.isRecent)
        running.names = ["owner"]
        let receipt = await engine.clean(entryIDs: [entry.id], includingRecent: [entry.id])
        #expect(receipt.items.first?.failure == .inUse && FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aCacheChangedAfterTheCheckStays() async throws {
        let fixture = try RecentFixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/fresh", "cached")
        let engine = fixture.engine(age: week, processes: ["owner"])
        let entry = try #require(await engine.scan().groups.first?.entries.first)
        _ = try fixture.write("cache/fresh", "written again, and longer")
        let receipt = await engine.clean(entryIDs: [entry.id], includingRecent: [entry.id])
        #expect(receipt.trashedCount == 0 && FileManager.default.fileExists(atPath: file.path))
    }

    @Test func structuralHoldsNeverBecomeSelectable() async throws {
        let fixture = try RecentFixture()
        defer { fixture.remove() }
        let target = try fixture.write("elsewhere/real", "kept")
        let linked = fixture.base.appendingPathComponent("cache/linked", isDirectory: true)
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("link"), withDestinationURL: target)
        let entry = try #require(await fixture.engine(age: week, processes: ["owner"]).scan().groups.first?.entries.first)
        #expect(!entry.eligibility.isSelectable && !entry.eligibility.isRecent && !entry.eligibility.isInUse)
    }

    @Test func aCacheThatNamesNoOwnerKeepsItsAgeRule() async throws {
        // With no app to watch for, a fresh file could be in use right now.
        let fixture = try RecentFixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/fresh", "cached")
        let engine = fixture.engine(age: week, processes: [])
        let entry = try #require(await engine.scan().groups.first?.entries.first)
        #expect(!entry.eligibility.isSelectable)
    }

    @Test func anOldCacheIsStillTickedForYou() async throws {
        let fixture = try RecentFixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/old", "cached")
        let report = await fixture.engine(age: 0, processes: ["owner"]).scan()
        #expect(report.eligibleEntries.count == 1 && report.groups.first?.recentEntries.isEmpty == true)
    }
}

private final class RunningNames: Sendable {
    private let state = Mutex<[String]>([])
    var names: [String] {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

private struct RecentFixture {
    let base: URL
    var cache: URL { base.appendingPathComponent("cache", isDirectory: true) }

    init() throws {
        base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("RoomRecent-\(UUID().uuidString)", isDirectory: true)
        for name in ["cache", "fixture-trash"] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    func write(_ relative: String, _ content: String) throws -> URL {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }

    func engine(age: TimeInterval, processes: [String], running: [String] = []) -> CacheEngine {
        let names = RunningNames()
        names.names = running
        return engine(age: age, processes: processes, running: names)
    }

    func engine(age: TimeInterval, processes: [String], running: RunningNames) -> CacheEngine {
        let trash = base.appendingPathComponent("fixture-trash", isDirectory: true)
        let root = CacheRoot(id: "fixture", title: "Fixture", subtitle: "", symbol: "archivebox",
            category: "developer", url: cache, consequence: "Test only", minimumAge: age, guardedProcesses: processes)
        return CacheEngine(configuration: CacheConfiguration(roots: [root], homeDirectory: base),
            activityDirectory: base.appendingPathComponent("activity", isDirectory: true),
            processProvider: { running.names }, fixtureTrashDirectory: trash,
            trashProvider: { original in
                let destination = trash.appendingPathComponent(UUID().uuidString)
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            })
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}
