import CryptoKit
import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Verified immutable npm content")
struct NPMContentPolicyTests {
    @Test("Only old addressed leaves mint; unavailable process observations are not fabricated")
    func verifiedLeafAndAge() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let old = try f.content(Data("old download".utf8))
        let young = try f.content(Data("recent download".utf8), old: false)
        let corrupt = try f.addressed(Data("address".utf8), actual: Data("different bytes".utf8))
        let calls = Mutex(0)
        let roots = [old, young, corrupt].map { f.root($0.deletingLastPathComponent()) }
        let unique = Dictionary(roots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.map { $0 }
        let engine = f.engine(roots: unique, processes: {
            calls.withLock { $0 += 1 }
            throw NPMTestError.unavailable
        })
        let report = await engine.scan()
        #expect(report.eligibleEntries.map(\.url) == [old])
        #expect(calls.withLock { $0 } == 0)
        #expect(report.groups.flatMap(\.entries).first { $0.url == young }?.eligibility.reason?.contains("Modified within") == true)
        #expect(report.groups.flatMap(\.entries).first { $0.url == corrupt }?.eligibility.reason?.contains("SHA512 address") == true)
        #expect(try await engine.authorizationLocations(entryIDs: report.eligibleEntries.map(\.id)) == [old.deletingLastPathComponent()])
        #expect(report.groups.allSatisfy { $0.consequence.contains("offline installs may fail") })
        #expect(NPMContentPolicy.expectedDigest(originalURL: old.deletingLastPathComponent(), root: f.root(old.deletingLastPathComponent())) == nil)
    }

    @Test("Links, special files, unsafe permissions, unknown names and oversized objects stay held")
    func unsupportedObjects() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let hard = try f.content(Data("hardlinked download".utf8))
        try FileManager.default.linkItem(at: hard, to: f.home.appendingPathComponent("shared"))
        let link = try f.address(Data("linked bytes".utf8))
        let outside = try f.write("outside", Data("linked bytes".utf8))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let pipe = try f.address(Data("named pipe".utf8))
        #expect(mkfifo(pipe.path, 0o600) == 0)
        let unsafe = try f.content(Data("group writable".utf8))
        #expect(chmod(unsafe.path, 0o666) == 0)
        let huge = try f.address(Data("oversize sparse file".utf8))
        #expect(FileManager.default.createFile(atPath: huge.path, contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(NPMContentLimits.standard.maximumFileBytes + 1)); try handle.close()
        try f.age(huge)
        let folder = try f.address(Data("directory".utf8))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let unknown = try f.write(String(hard.deletingLastPathComponent().path.dropFirst(f.home.path.count + 1)) + "/README", Data("keep".utf8))
        let roots = [hard, link, pipe, unsafe, huge, folder].map { f.root($0.deletingLastPathComponent()) }
        let report = await f.engine(roots: roots).scan()
        #expect(report.eligibleEntries.isEmpty)
        let entries = report.groups.flatMap(\.entries)
        #expect(entries.first { $0.url == huge }?.eligibility.reason?.contains("bounded content-read") == true)
        #expect(entries.contains { $0.url == unknown })
        #expect(try Data(contentsOf: outside) == Data("linked bytes".utf8))
        #expect(await f.engine(roots: roots).clean(entryIDs: [UUID()]).trashedCount == 0)
    }

    @Test("The content rule refuses lookalike layouts and descriptor traversal through linked ancestors")
    func layoutAndAncestors() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let valid = try f.content(Data("layout bytes".utf8))
        let fakeBucket = try f.directory("Documents/_cacache/content-v2/sha512/aa/bb")
        let fake = fakeBucket.appendingPathComponent(String(repeating: "0", count: 124))
        try Data("document".utf8).write(to: fake); try f.age(fake)
        #expect(NPMContentPolicy.bucketPrefixes(fakeBucket) == nil)
        #expect(await f.engine(roots: [f.root(fakeBucket)]).scan().eligibleEntries.isEmpty)
        let realPrefix = valid.deletingLastPathComponent().deletingLastPathComponent()
        let moved = realPrefix.appendingPathExtension("real")
        try FileManager.default.moveItem(at: realPrefix, to: moved)
        try FileManager.default.createSymbolicLink(at: realPrefix, withDestinationURL: moved)
        let report = await f.engine(roots: [f.root(valid.deletingLastPathComponent())]).scan()
        #expect(report.eligibleEntries.isEmpty && !report.issues.isEmpty)
        #expect(NPMContentPolicy.hex("AA", count: 2) == false)
        #expect(NPMContentPolicy.hex("a/", count: 2) == false)
    }

    @Test("Byte, file, time and cancellation bounds cannot create unverifiable cleanup IDs")
    func boundsAndCancellation() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let item = try f.content(Data("bounded object".utf8))
        let root = f.root(item.deletingLastPathComponent())
        for limits in [NPMContentLimits(maximumScanBytes: 0), NPMContentLimits(maximumFiles: 0), NPMContentLimits(timeLimit: 0)] {
            let report = await f.engine(roots: [root], limits: limits).scan()
            #expect(report.eligibleEntries.isEmpty)
            #expect(report.isPartial)
        }
        let small = await f.engine(roots: [root], limits: NPMContentLimits(maximumFileBytes: 1)).scan()
        #expect(small.eligibleEntries.isEmpty)
        let engine = f.engine(roots: [root])
        let task = Task { await engine.scan() }
        task.cancel()
        let cancelled = await task.value
        #expect(cancelled.cancelled && cancelled.eligibleEntries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: item.path))
    }

    @Test("The immutable exception preserves protected-location and parent-permission holds")
    func protectedAndParentPermissions() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let item = try f.content(Data("protected download".utf8))
        let root = f.root(item.deletingLastPathComponent())
        let protected = CacheConfiguration(roots: [root], protectedLocations: [
            ProtectedLocation(id: "explicit-protection", title: "Keep", url: item, reason: "Explicitly protected")
        ], homeDirectory: f.home)
        #expect(await f.engine(configuration: protected).scan().eligibleEntries.isEmpty)
        #expect(chmod(root.url.path, 0o777) == 0)
        let unsafe = await f.engine(roots: [root]).scan()
        #expect(unsafe.eligibleEntries.isEmpty)
        #expect(unsafe.groups.first?.entries.first?.eligibility.reason?.contains("parent") == true)
    }

    @Test("Content checks reject same-size rewrites even when mtime is preserved")
    func digestAuthenticatesBytes() throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let original = Data("first bytes".utf8)
        let item = try f.content(original)
        try Data("other bytes".utf8).write(to: item)
        try f.age(item)
        var metadata = stat()
        #expect(lstat(item.path, &metadata) == 0)
        #expect(throws: (any Error).self) {
            try NPMContentPolicy.verify(source: item, originalURL: item, root: f.root(item.deletingLastPathComponent()),
                identity: NPMContentPolicy.identity(metadata), budget: NPMContentBudget())
        }
    }

    @Test("Cleanup revalidates stale IDs, changed bytes and replaced prefix parents")
    func freshness() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let item = try f.content(Data("freshness".utf8))
        let root = f.root(item.deletingLastPathComponent())
        let engine = f.engine(roots: [root])
        let first = await engine.scan()
        let stale = Set(first.eligibleEntries.map(\.id))
        let second = await engine.scan()
        #expect(await engine.clean(entryIDs: stale).trashedCount == 0)
        try Data("different".utf8).write(to: item); try f.age(item)
        #expect(await engine.clean(entryIDs: Set(second.eligibleEntries.map(\.id))).trashedCount == 0)
        try Data("freshness".utf8).write(to: item); try f.age(item)
        let third = await engine.scan()
        let moved = root.url.appendingPathExtension("saved")
        try FileManager.default.moveItem(at: root.url, to: moved)
        try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: false)
        #expect(await engine.clean(entryIDs: Set(third.eligibleEntries.map(\.id))).trashedCount == 0)
        #expect(try Data(contentsOf: moved.appendingPathComponent(item.lastPathComponent)) == Data("freshness".utf8))
    }

    @Test("Individual-file receipts survive restart, Restore preserves bytes and never overwrites")
    func restartRestore() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let bytes = Data("recoverable package bytes".utf8)
        let item = try f.content(bytes)
        let root = f.root(item.deletingLastPathComponent())
        let engine = f.engine(roots: [root])
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        let moved = try #require(receipt.items.first?.trashURL)
        #expect(moved.lastPathComponent != item.lastPathComponent)
        #expect(try Data(contentsOf: moved) == bytes)
        let restarted = f.engine(roots: [root])
        #expect(try await restarted.restoreAuthorizationLocations(receiptID: receipt.id) == [root.url])
        let restored = await restarted.restore(receiptID: receipt.id, approvedTrashItems: [moved])
        try #require(restored.restoredCount == 1, "Restore issues: \(restored.issues.map(\.message))")
        #expect(try Data(contentsOf: item) == bytes)
        let again = await restarted.scan()
        let second = await restarted.clean(entryIDs: Set(again.eligibleEntries.map(\.id)))
        try Data("newer installed cache value".utf8).write(to: item)
        #expect(await f.engine(roots: [root]).restore(receiptID: second.id, approvedTrashItems: second.items.compactMap(\.trashURL)).restoredCount == 0)
        #expect(try Data(contentsOf: item) == Data("newer installed cache value".utf8))
    }

    @Test("Restore authenticates content despite Finder-tolerated ctime drift")
    func restoreDigestTamper() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let item = try f.content(Data("first bytes".utf8))
        let root = f.root(item.deletingLastPathComponent())
        let engine = f.engine(roots: [root])
        let report = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        let moved = try #require(receipt.items.first?.trashURL)
        let date = try #require(try FileManager.default.attributesOfItem(atPath: moved.path)[.modificationDate] as? Date)
        // An in-place rewrite keeps the inode; mtime is restored deliberately.
        let handle = try FileHandle(forWritingTo: moved)
        try handle.write(contentsOf: Data("other bytes".utf8)); try handle.close()
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: moved.path)
        let restored = await f.engine(roots: [root]).restore(receiptID: receipt.id, approvedTrashItems: [moved])
        #expect(restored.restoredCount == 0)
        #expect(restored.issues.contains { $0.message.contains("SHA512 address") }, "Actual Restore issues: \(restored.issues.map(\.message))")
        #expect(!FileManager.default.fileExists(atPath: item.path))
    }
}

#if ROOM_APP_STORE
@Suite("Store npm prefix approval")
struct StoreNPMPrefixTests {
    @Test("Exact native bucket approval enables only its verified leaf and keeps every other family held")
    func exactBucket() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let item = try f.content(Data("exact bucket".utf8))
        let other = try f.content(Data("unapproved sibling".utf8))
        let bucket = item.deletingLastPathComponent()
        let config = CacheConfiguration.store(approvedFolders: [bucket], userHome: f.home)
        #expect(config.roots.count == 1)
        #expect(config.roots.first?.contentValidation == .npmSHA512)
        let report = await CacheEngine(configurationProvider: { config }, activityDirectory: f.activity, trashHomeDirectory: f.home).scan()
        #expect(report.eligibleEntries.map(\.url) == [item])
        #expect(report.groups.flatMap(\.entries).allSatisfy { $0.url != other })
        for approved in [bucket.deletingLastPathComponent(), bucket.deletingLastPathComponent().deletingLastPathComponent()] {
            let scoped = CacheConfiguration.store(approvedFolders: [approved], userHome: f.home)
            #expect(scoped.roots.contains { $0.url == bucket && $0.contentValidation == .npmSHA512 })
            #expect(scoped.roots.allSatisfy { $0.url.path == approved.path || $0.url.path.hasPrefix(approved.path + "/") })
        }
        _ = try f.write("Library/Caches/Homebrew/archive", Data("old guarded data".utf8))
        let broad = CacheConfiguration.store(approvedFolders: [f.home], userHome: f.home)
        let all = await CacheEngine(configurationProvider: { broad }, activityDirectory: f.activity, trashHomeDirectory: f.home).scan()
        #expect(all.eligibleEntries.allSatisfy { $0.url.path.contains("/_cacache/content-v2/sha512/") })
        #expect(all.groups.first { $0.id == "homebrew" }?.entries.first?.eligibility.reason?.contains("App Store sandbox") == true)
        #expect(try Data(contentsOf: other) == Data("unapproved sibling".utf8))
    }

    @Test("Parent and overlapping prefix grants count content once and leave index, tmp and unknown formats intact")
    func inventoryAndOverlap() async throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let item = try f.content(Data("counted once".utf8))
        let index = try f.write(".npm/_cacache/index-v5/aa/bb/entry", Data("index state".utf8))
        let temp = try f.write(".npm/_cacache/tmp/active", Data("unfinished work".utf8))
        let unknown = try f.write(".npm/_cacache/content-v3/sha512/object", Data("future format".utf8))
        let parent = f.home.appendingPathComponent(".npm")
        let config = CacheConfiguration.store(approvedFolders: [parent, item.deletingLastPathComponent(), parent], userHome: f.home)
        #expect(config.readAccessRoots?.count == 1)
        let report = await f.engine(configuration: config).scan()
        #expect(report.eligibleEntries.map(\.url) == [item])
        let expected = try [item, index, temp, unknown].reduce(Int64(0)) { value, url in
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw NPMTestError.unavailable }
            return value + Int64(info.st_blocks) * 512
        }
        #expect(report.totalBytes == expected)
        #expect(report.groups.first { $0.id == "npm" }?.isInspectionOnly == true)
        let receipt = await f.engine(configuration: config).clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 0) // IDs from a different engine are never trusted.
        #expect(try Data(contentsOf: index) == Data("index state".utf8))
        #expect(try Data(contentsOf: temp) == Data("unfinished work".utf8))
        #expect(try Data(contentsOf: unknown) == Data("future format".utf8))
    }

    @Test("Prefix discovery is bounded and never promotes a linked, lookalike or wrong-home bucket")
    func discoveryBoundaries() throws {
        let f = try NPMFixture()
        defer { f.remove() }
        let item = try f.content(Data("approval boundaries".utf8))
        let bucket = item.deletingLastPathComponent()
        let wrongHome = try f.directory("container/Data")
        let wrong = CacheConfiguration.store(approvedFolders: [bucket], userHome: wrongHome)
        #expect(wrong.roots.allSatisfy { $0.contentValidation == nil })
        let alias = f.home.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: bucket)
        #expect(CacheConfiguration.store(approvedFolders: [alias], userHome: f.home).roots.isEmpty)
        for index in 0..<300 {
            let prefix = String(format: "%04x", index)
            _ = try f.directory(".npm/_cacache/content-v2/sha512/\(prefix.prefix(2))/\(prefix.suffix(2))")
        }
        let result = StoreNPMCatalogue.discover(approvedFolders: [f.home.appendingPathComponent(".npm")], userHome: f.home)
        #expect(result.roots.count <= 256)
        #expect(!result.issues.isEmpty)
        #expect(result.roots.allSatisfy { NPMContentPolicy.bucketPrefixes($0.url) != nil })
    }
}
#endif

private enum NPMTestError: Error { case unavailable }

private struct NPMFixture: Sendable {
    let home: URL
    var activity: URL { home.appendingPathComponent("receipts") }
    var trash: URL { home.appendingPathComponent("trash") }
    init() throws {
        home = URL(fileURLWithPath: "/private/tmp/RoomNPM-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
    }
    func directory(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func write(_ relative: String, _ data: Data) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url); try age(url)
        return url
    }
    func age(_ url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: url.path)
    }
    func address(_ bytes: Data) throws -> URL {
        let digest = SHA512.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let bucket = try directory(".npm/_cacache/content-v2/sha512/\(digest.prefix(2))/\(digest.dropFirst(2).prefix(2))")
        return bucket.appendingPathComponent(String(digest.dropFirst(4)))
    }
    func content(_ bytes: Data, old: Bool = true) throws -> URL {
        let url = try address(bytes)
        try bytes.write(to: url)
        if old { try age(url) }
        return url
    }
    func addressed(_ addressBytes: Data, actual: Data) throws -> URL {
        let url = try address(addressBytes)
        try actual.write(to: url); try age(url)
        return url
    }
    func root(_ bucket: URL) -> CacheRoot {
        CacheRoot(id: bucket.path, title: "npm content fixture", subtitle: "Owned fixture", symbol: "shippingbox",
            category: "developer", url: bucket, consequence: NPMContentPolicy.consequence,
            minimumAge: 0, contentValidation: .npmSHA512)
    }
    func engine(roots: [CacheRoot] = [], configuration: CacheConfiguration? = nil,
                limits: NPMContentLimits = .standard,
                processes: @escaping @Sendable () throws -> [String] = { throw NPMTestError.unavailable }) -> CacheEngine {
        let trash = self.trash
        return CacheEngine(configuration: configuration ?? CacheConfiguration(roots: roots, homeDirectory: home),
            activityDirectory: activity, processProvider: processes, fixtureTrashDirectory: trash,
            trashProvider: { source in
                let target = trash.appendingPathComponent(UUID().uuidString)
                try FileManager.default.moveItem(at: source, to: target)
                return target
            }, npmContentLimits: limits)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
