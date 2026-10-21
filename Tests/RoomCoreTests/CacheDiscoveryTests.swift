import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Full cache discovery and independent cache units", .serialized)
struct CacheDiscoveryTests {
    @Test("Broad cache, log and temp inventory stays read-only and does not duplicate known or protected bytes")
    func discoveryExclusions() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let known = try fixture.write("Library/Caches/Known/archive.bin", count: 8_000)
        let unknown = try fixture.write("Library/Caches/Unknown/resource.bin", count: 12_000)
        let protected = try fixture.write("Library/Caches/Protected/history.bin", count: 16_000)
        _ = try fixture.write(".cache/model-store/weights.bin", count: 20_000)
        _ = try fixture.write("user-temp/unfinished.bin", count: 24_000)
        _ = try fixture.write("Library/Logs/App/log.txt", count: 28_000)
        let base = CacheConfiguration(roots: [fixture.root(path: "Library/Caches/Known")], protectedLocations: [
            ProtectedLocation(id: "history", title: "Recovery", url: protected.deletingLastPathComponent(), reason: "Recovery work")
        ], homeDirectory: fixture.home)
        let config = fixture.full(base)
        let engine = fixture.engine(config)
        let report = await engine.scan()
        #expect(report.issues.isEmpty)
        #expect(report.eligibleEntries.map(\.url) == [known])
        let inspected = try #require(report.groups.first { $0.id == "discovered-app-caches" })
        #expect(inspected.entries.map(\.name) == ["Unknown"])
        #expect(inspected.totalBytes == (try fixture.allocated(unknown)))
        #expect(report.protectedData.first?.byteCount == (try fixture.allocated(protected)))
        #expect(report.groups.first { $0.id == "discovered-hidden-caches" }?.totalBytes ?? 0 > 0)
        #expect(report.groups.first { $0.id == "discovered-temporary" }?.totalBytes ?? 0 > 0)
        #expect(report.groups.first { $0.id == "discovered-logs" }?.totalBytes ?? 0 > 0)
        let forged = await engine.clean(entryIDs: Set(report.groups.filter { $0.id.hasPrefix("discovered-") }.flatMap { $0.entries.map(\.id) }))
        #expect(forged.items.isEmpty)
        #expect(fixture.moves.withLock { $0 } == 0)
        #expect(FileManager.default.fileExists(atPath: unknown.path))
    }

    @Test("OS-supplied temporary and cache roots retain physical paths without a var alias")
    func physicalSystemRoots() throws {
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
        try #require((2..<16_384).contains(length))
        var buffer = [CChar](repeating: 0, count: length)
        try #require(confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, length) > 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let userCache = URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self), isDirectory: true)
        // This checks OS path canonicalization, independently of app catalogue
        // discovery and the permissions of unrelated installed applications.
        let config = CacheConfiguration.addingDiscoveredSources(to: CacheConfiguration(roots: []),
            temporaryDirectory: FileManager.default.temporaryDirectory, userCacheDirectory: userCache)
        for id in ["temporary-karma", "discovered-temporary", "discovered-user-cache"] {
            let root = config.roots.first { $0.id == id }
            #expect(root != nil)
            guard let root else { continue }
            var cursor = root.url
            while cursor.path != "/" {
                var metadata = stat()
                #expect(lstat(cursor.path, &metadata) == 0)
                #expect(metadata.st_mode & UInt16(S_IFMT) != UInt16(S_IFLNK), "\(id) has a symbolic-link ancestor: \(cursor.path)")
                cursor.deleteLastPathComponent()
            }
        }
    }

    @Test("Automatic temporary and user-cache overrides cannot enter app containers")
    func containerSystemDirectoryOverridesRequireApproval() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let cache = try fixture.write("Library/Containers/com.example.app/Data/Library/Caches/resource", count: 8_000)
        let temporary = try fixture.write("Library/Group Containers/group.example.app/temporary/_karma_webpack_123/data", count: 12_000)
        let config = CacheConfiguration.addingDiscoveredSources(to: CacheConfiguration(roots: [], homeDirectory: fixture.home),
            temporaryDirectory: temporary.deletingLastPathComponent().deletingLastPathComponent(),
            userCacheDirectory: cache.deletingLastPathComponent())
        #expect(!config.roots.contains { ["temporary-karma", "discovered-temporary", "discovered-user-cache"].contains($0.id) })
        #expect(config.inspectionIssues.contains { $0.message.contains("folder approval") })
    }

    @Test("Trusted parent aliases are normalized while discovered child links remain untraversed")
    func trustedParentAlias() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let file = try fixture.write("user-temp/cache.bin", count: 8_000)
        let outside = try fixture.write("outside/user-work.bin", count: 24_000)
        let alias = fixture.home.appendingPathComponent("temp-alias", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.temporary)
        try FileManager.default.createSymbolicLink(at: fixture.temporary.appendingPathComponent("child-link", isDirectory: false),
            withDestinationURL: outside.deletingLastPathComponent())
        let config = CacheConfiguration.addingDiscoveredSources(to: CacheConfiguration(roots: [], homeDirectory: fixture.home),
            temporaryDirectory: alias, inspectionTimeLimit: 60)
        #expect(config.roots.first { $0.id == "discovered-temporary" }?.url.path == fixture.temporary.path)
        let report = await fixture.engine(config).scan()
        #expect(report.totalBytes == (try fixture.allocated(file)))
        #expect(report.eligibleEntries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("Inspect-only size budgets return visible lower bounds without limiting known cleanup verification")
    func boundedInspection() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        _ = try fixture.write("Library/Caches/Known/complete.bin", count: 8_000)
        for name in ["a", "b", "c", "d"] { _ = try fixture.write("Library/Caches/Unknown/\(name)", count: 8_000) }
        let base = CacheConfiguration(roots: [fixture.root(path: "Library/Caches/Known")], homeDirectory: fixture.home)
        let full = await fixture.engine(fixture.full(base)).scan()
        let bounded = fixture.full(base, nodes: 2)
        let limited = await fixture.engine(bounded).scan()
        let group = try #require(limited.groups.first { $0.id == "discovered-app-caches" })
        #expect(group.isPartial)
        #expect(limited.isPartial)
        #expect(group.totalBytes > 0)
        #expect(group.totalBytes < full.groups.first { $0.id == group.id }?.totalBytes ?? 0)
        #expect(group.consequence.contains("lower bound"))
        #expect(limited.eligibleBytes == full.eligibleBytes)
        #expect(group.eligibleEntries.isEmpty)
    }

    @Test("Old independent cache units remain eligible beside a fresh unit and round-trip through receipts")
    func independentAgedUnits() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let old = try fixture.write("cache/version/old-unit/data", count: 8_000)
        let fresh = try fixture.write("cache/version/new-unit/data", count: 12_000)
        try fixture.age(old)
        try fixture.age(old.deletingLastPathComponent())
        let root = fixture.root(path: "cache", age: 7 * 86_400, depth: 3)
        let engine = fixture.engine(CacheConfiguration(roots: [root], homeDirectory: fixture.home))
        let report = await engine.scan()
        #expect(report.issues.isEmpty)
        #expect(report.totalBytes == (try fixture.allocated(old)) + (try fixture.allocated(fresh)))
        #expect(report.groups.first?.entries.reduce(0) { $0 + $1.fileCount } == 2)
        #expect(report.eligibleEntries.map { $0.url.path } == [old.deletingLastPathComponent().path])
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1, "\(receipt.issues)")
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(await engine.restore(receiptID: receipt.id).restoredCount == 1)
        #expect(FileManager.default.fileExists(atPath: old.path))
    }

    @Test("Nested cache freshness and replaced ancestors are still revalidated immediately before cleanup")
    func nestedRevalidation() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let old = try fixture.write("cache/version/old-unit/data", count: 8_000)
        _ = try fixture.write("cache/version/fresh-unit/data", count: 4_000)
        try fixture.age(old); try fixture.age(old.deletingLastPathComponent())
        let config = CacheConfiguration(roots: [fixture.root(path: "cache", age: 7 * 86_400, depth: 3)], homeDirectory: fixture.home)
        let engine = fixture.engine(config)
        let before = await engine.scan()
        #expect(before.eligibleEntries.count == 1)
        try Data("changed since scan".utf8).write(to: old)
        let result = await engine.clean(entryIDs: Set(before.eligibleEntries.map(\.id)))
        #expect(result.trashedCount == 0)
        #expect(fixture.moves.withLock { $0 } == 0)
        #expect(FileManager.default.fileExists(atPath: old.path))
    }

    @Test("Nested recovery refuses both symlinked and newly replaced original parents")
    func nestedRestoreParentBoundaries() async throws {
        for useSymlink in [true, false] {
            let fixture = try DiscoveryFixture()
            defer { fixture.remove() }
            let old = try fixture.write("cache/version/old-unit/data", count: 8_000)
            _ = try fixture.write("cache/version/fresh-unit/data", count: 4_000)
            try fixture.age(old); try fixture.age(old.deletingLastPathComponent())
            let config = CacheConfiguration(roots: [fixture.root(path: "cache", age: 7 * 86_400, depth: 3)], homeDirectory: fixture.home)
            let engine = fixture.engine(config)
            let report = await engine.scan()
            let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
            #expect(receipt.trashedCount == 1)
            #expect(receipt.items.first?.originalParentIdentity != nil)
            let parent = old.deletingLastPathComponent().deletingLastPathComponent()
            let previous = parent.deletingLastPathComponent().appendingPathComponent("previous-version", isDirectory: true)
            try FileManager.default.moveItem(at: parent, to: previous)
            let outside = try fixture.directory("outside")
            if useSymlink { try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outside) }
            else { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false) }
            let restored = await fixture.engine(config).restore(receiptID: receipt.id)
            #expect(restored.restoredCount == 0)
            #expect(!restored.issues.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("old-unit", isDirectory: false).path))
            #expect(!FileManager.default.fileExists(atPath: old.path))
            let trashURL = try #require(receipt.items.first?.trashURL)
            #expect(FileManager.default.fileExists(atPath: trashURL.path))
        }
    }

    @Test("Active owners still block every nested cleanup unit")
    func activeOwner() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let old = try fixture.write("cache/version/old-unit/data", count: 8_000)
        _ = try fixture.write("cache/version/new-unit/data", count: 4_000)
        try fixture.age(old); try fixture.age(old.deletingLastPathComponent())
        let config = CacheConfiguration(roots: [fixture.root(path: "cache", age: 7 * 86_400, depth: 3, processes: ["node"])], homeDirectory: fixture.home)
        let report = await fixture.engine(config, processes: { ["/usr/local/bin/node"] }).scan()
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.totalBytes > 0)
    }

    @Test("A partition-unit cap retains every measured byte in a held containing row")
    func boundedPartitionTotals() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        var bytes: Int64 = 0
        for index in 0..<6 {
            let file = try fixture.write("cache/version/unit-\(index)/data", count: 8_000)
            bytes += try fixture.allocated(file)
            if index != 5 { try fixture.age(file); try fixture.age(file.deletingLastPathComponent()) }
        }
        let config = CacheConfiguration(roots: [fixture.root(path: "cache", age: 7 * 86_400, depth: 3)], homeDirectory: fixture.home)
        let report = await fixture.engine(config, partitionLimit: 2).scan()
        #expect(report.totalBytes == bytes)
        #expect(report.groups.first?.entries.reduce(0) { $0 + $1.fileCount } == 6)
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.groups.first?.entries.count == 1)
    }

    @Test("Protected subtrees cannot be cleaned through a broader explicitly allowed root")
    func protectedIntersections() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/unit/recovery/history", count: 8_000)
        let config = CacheConfiguration(roots: [fixture.root(path: "cache")], protectedLocations: [
            ProtectedLocation(id: "recovery", title: "Recovery", url: file.deletingLastPathComponent(), reason: "Keep")
        ], homeDirectory: fixture.home)
        let engine = fixture.engine(config)
        let report = await engine.scan()
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.groups.first?.entries.first?.eligibility.reason?.contains("protected") == true)
        let result = await engine.clean(entryIDs: Set(report.groups.flatMap { $0.entries.map(\.id) }))
        #expect(result.trashedCount == 0)
        #expect(fixture.moves.withLock { $0 } == 0)
    }

    @Test("Progress is real and cannot authorize cleanup before the final complete report")
    func progressDoesNotMintIDs() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/archive", count: 8_000)
        let engine = fixture.engine(CacheConfiguration(roots: [fixture.root(path: "cache")], homeDirectory: fixture.home))
        let events = Mutex<[CacheScanProgress]>([])
        let rejected = Mutex(false)
        let report = await engine.scan(progress: { value in
            events.withLock { $0.append(value) }
            #expect(value.partialReport.cancelled)
            #expect(value.partialReport.eligibleEntries.isEmpty)
            let ids = Set(value.partialReport.groups.flatMap { $0.entries.map(\.id) })
            if !ids.isEmpty {
                let result = await engine.clean(entryIDs: ids)
                rejected.withLock { $0 = result.items.isEmpty }
            }
        })
        #expect(rejected.withLock { $0 })
        #expect(report.eligibleEntries.map(\.url) == [file])
        let recorded = events.withLock { $0 }
        #expect(recorded.first?.completedRoots == 0)
        #expect(recorded.last?.completedRoots == recorded.last?.totalRoots)
        #expect(fixture.moves.withLock { $0 } == 0)
    }

    @Test("Cancelling from partial progress preserves measurements and revokes every cleanup ID")
    func cancelledProgress() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/archive", count: 8_000)
        let engine = fixture.engine(CacheConfiguration(roots: [fixture.root(path: "cache")], homeDirectory: fixture.home))
        let task = Task {
            await engine.scan(progress: { value in
                if !value.partialReport.groups.isEmpty { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        let report = await task.value
        #expect(report.cancelled)
        #expect(report.totalBytes == (try fixture.allocated(file)))
        #expect(report.eligibleEntries.isEmpty)
        let result = await engine.clean(entryIDs: Set(report.groups.flatMap { $0.entries.map(\.id) }))
        #expect(result.trashedCount == 0)
        #expect(fixture.moves.withLock { $0 } == 0)
    }

    @Test("Karma matching is an exact generated directory family and restoration survives a clean relaunch")
    func stableKarmaFamily() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let old = try fixture.write("user-temp/_karma_webpack_123/bundle.js", count: 8_000)
        try fixture.age(old); try fixture.age(old.deletingLastPathComponent())
        let other = try fixture.write("user-temp/_karma_webpack_personal/source.js", count: 12_000)
        _ = try fixture.write("user-temp/_karma_webpack_1234567/source.js", count: 4_000)
        _ = try fixture.write("user-temp/_karma_webpack_999", count: 4_000)
        let outside = try fixture.directory("outside")
        try FileManager.default.createSymbolicLink(at: fixture.temporary.appendingPathComponent("_karma_webpack_456", isDirectory: false), withDestinationURL: outside)
        let config = fixture.full(CacheConfiguration(roots: [], homeDirectory: fixture.home))
        let engine = fixture.engine(config)
        let report = await engine.scan()
        #expect(report.eligibleEntries.map { $0.url.path } == [old.deletingLastPathComponent().path])
        #expect(report.groups.first { $0.id == "discovered-temporary" }?.entries.allSatisfy { $0.url.path != old.deletingLastPathComponent().path } == true)
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1, "\(receipt.issues)")
        let rebuilt = fixture.full(CacheConfiguration(roots: [], homeDirectory: fixture.home))
        #expect(rebuilt.roots.contains { $0.id == "temporary-karma" })
        let newEngine = fixture.engine(rebuilt)
        #expect(await newEngine.restore(receiptID: receipt.id).restoredCount == 1)
        #expect(FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test("New generated folders after configuration and between rescans are counted exactly once")
    func liveFamilyExclusions() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let config = fixture.full(CacheConfiguration(roots: [], homeDirectory: fixture.home))
        let first = try fixture.write("user-temp/_karma_webpack_123/bundle.js", count: 8_000)
        let unknown = try fixture.write("user-temp/unclassified/data", count: 4_000)
        let engine = fixture.engine(config)
        let report = await engine.scan()
        #expect(report.totalBytes == (try fixture.allocated(first)) + (try fixture.allocated(unknown)))
        #expect(report.groups.first { $0.id == "discovered-temporary" }?.entries.map(\.name) == ["unclassified"])
        let second = try fixture.write("user-temp/_karma_webpack_456/bundle.js", count: 12_000)
        let refreshed = await engine.scan()
        #expect(refreshed.totalBytes == (try fixture.allocated(first)) + (try fixture.allocated(second)) + (try fixture.allocated(unknown)))
        #expect(refreshed.groups.first { $0.id == "discovered-temporary" }?.entries.map(\.name) == ["unclassified"])
    }

    @Test("Discovery never promotes unknown hidden stores or arbitrary temp siblings to known caches")
    func classificationBoundaries() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.remove() }
        let config = fixture.full(CacheConfiguration(roots: [], homeDirectory: fixture.home))
        func item(_ path: String) -> DiskMapItem {
            DiskMapItem(url: fixture.home.appendingPathComponent(path, isDirectory: false), name: "item", isDirectory: false,
                allocatedBytes: 4_096, logicalBytes: 1_000, fileCount: 1)
        }
        #expect(StorageAnalyzer.finding(for: item(".cache/models/weights.bin"), configuration: config).disposition != .cache)
        #expect(StorageAnalyzer.finding(for: item("user-temp/unfinished-project/source.bin"), configuration: config).disposition != .cache)
        #expect(StorageAnalyzer.finding(for: item("user-temp/_karma_webpack_123/bundle.js"), configuration: config).disposition == .cache)
        #expect(StorageAnalyzer.finding(for: item("user-temp/_karma_webpack_personal/source.bin"), configuration: config).disposition != .cache)
    }
}

private final class DiscoveryFixture: Sendable {
    let home = URL(fileURLWithPath: "/private/tmp/RoomDiscovery-\(UUID().uuidString)", isDirectory: true)
    let moves = Mutex(0)
    var temporary: URL { home.appendingPathComponent("user-temp", isDirectory: true) }
    var trash: URL { home.appendingPathComponent("fixture-trash", isDirectory: true) }
    var activity: URL { home.appendingPathComponent("activity", isDirectory: true) }
    init() throws { _ = try directory(""); _ = try directory("user-temp"); _ = try directory("fixture-trash") }
    func directory(_ path: String) throws -> URL {
        let url = home.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func write(_ path: String, count: Int) throws -> URL {
        let url = home.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: count).write(to: url)
        return url
    }
    func age(_ url: URL) throws { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: url.path) }
    func allocated(_ url: URL) throws -> Int64 { var value = stat(); #expect(lstat(url.path, &value) == 0); return Int64(value.st_blocks) * 512 }
    func root(path: String, age: TimeInterval = 0, depth: Int = 1, processes: [String] = []) -> CacheRoot {
        CacheRoot(id: "known", title: "Known cache", subtitle: path, symbol: "archivebox", category: "developer",
            url: home.appendingPathComponent(path, isDirectory: true), consequence: "Rebuilds", minimumAge: age,
            guardedProcesses: processes, candidateDepth: depth)
    }
    func full(_ base: CacheConfiguration, nodes: Int = 100_000) -> CacheConfiguration {
        CacheConfiguration.addingDiscoveredSources(to: base, temporaryDirectory: temporary,
            inspectionNodeLimit: nodes, inspectionTimeLimit: 60)
    }
    func engine(_ configuration: CacheConfiguration, processes: @escaping @Sendable () throws -> [String] = { [] }, partitionLimit: Int = 20_000) -> CacheEngine {
        let trash = self.trash
        let counter = self
        return CacheEngine(configuration: configuration, activityDirectory: activity, processProvider: processes,
            fixtureTrashDirectory: trash, candidatePartitionUnitLimit: partitionLimit, trashProvider: { original in
                counter.moves.withLock { $0 += 1 }
                let destination = trash.appendingPathComponent(UUID().uuidString + "-" + original.lastPathComponent, isDirectory: false)
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
