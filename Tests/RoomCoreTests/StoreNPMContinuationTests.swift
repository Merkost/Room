#if ROOM_APP_STORE
import CryptoKit
import Darwin
import Foundation
import Testing
@testable import RoomCore

@Suite("Bounded Store npm continuation")
struct StoreNPMContinuationTests {
    @Test("More than 256 populated buckets are reached once across explicit bounded batches")
    func populatedBucketsContinue() throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        for index in 0..<300 {
            let bucket = try fixture.bucket(index)
            // These deliberately unverified payloads test discovery, never eligibility.
            try Data("inventory fixture".utf8).write(to: bucket.appendingPathComponent(String(repeating: "0", count: 124)))
        }
        let result = try collect(fixture, approved: [fixture.npm])
        #expect(result.pages.count > 1)
        #expect(result.roots.count == 300)
        #expect(Set(result.roots.map(\.url.path)).count == 300)
        #expect(result.pages.reduce(0) { $0 + ($1.npmDiscovery?.inspectedBuckets ?? 0) } == 300)
        #expect(result.roots.allSatisfy {
            $0.contentValidation == .npmSHA512 && $0.minimumAge == NPMContentPolicy.minimumAge
                && $0.inspectionNodeLimit == 4_096 && $0.inspectionTimeLimit == 8
        })
    }

    @Test("Empty buckets count, advance the cursor, and cannot permanently hide a later valid object")
    func emptyBucketsDoNotStarveLaterContent() async throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        for index in 0..<300 { _ = try fixture.bucket(index) }
        let content = try fixture.lateContent()
        let originalBytes = try Data(contentsOf: content)
        let result = try collect(fixture, approved: [fixture.npm])
        #expect(result.pages.count > 1)
        #expect(result.roots.count == 301)
        #expect(result.pages.reduce(0) { $0 + ($1.npmDiscovery?.inspectedBuckets ?? 0) } == 301)
        let page = try #require(result.pages.first { configuration in
            configuration.roots.contains { $0.contentValidation == .npmSHA512 && $0.url == content.deletingLastPathComponent() }
        })
        let engine = CacheEngine(configuration: page, activityDirectory: fixture.home.appendingPathComponent("receipts"),
            processProvider: { [] }, fixtureTrashDirectory: fixture.home.appendingPathComponent("trash"))
        let report = await engine.scan()
        #expect(report.eligibleEntries.map(\.url) == [content])
        #expect(try Data(contentsOf: content) == originalBytes)
    }

    @Test("Sparse namespace pages advance through empty prefixes within the node budget")
    func sparsePrefixSpaceDoesNotRestart() throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        for first in 0..<256 {
            _ = try fixture.directory(".npm/_cacache/content-v2/sha512/" + String(format: "%02x", first))
        }
        let last = try fixture.bucket(0xffff)
        let result = try collect(fixture, approved: [fixture.npm])
        #expect(result.pages.count > 1)
        #expect(result.pages.contains { $0.npmDiscovery?.inspectedBuckets == 0 && $0.npmDiscovery?.hasMore == true })
        #expect(result.roots.map(\.url) == [last])
        #expect(result.pages.last?.npmDiscovery?.hasMore == false)
    }

    @Test("A continuation is rejected for changed approvals and replaced physical scope")
    func wrongScopeAndReplacementFailClosed() throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        for index in 0..<300 { _ = try fixture.bucket(index) }
        let first = CacheConfiguration.store(approvedFolders: [fixture.npm], userHome: fixture.home)
        let cursor = try #require(first.npmDiscovery?.nextCursor)
        let exact = fixture.bucketURL(0)
        let narrowed = CacheConfiguration.store(approvedFolders: [exact], userHome: fixture.home, npmContinuation: cursor)
        expectRejected(narrowed)
        let unrelated = try fixture.directory("Documents")
        let changed = CacheConfiguration.store(approvedFolders: [fixture.npm, unrelated], userHome: fixture.home, npmContinuation: cursor)
        expectRejected(changed)
        try FileManager.default.moveItem(at: fixture.npm, to: fixture.home.appendingPathComponent("preserved-npm"))
        _ = try fixture.directory(".npm")
        let replaced = CacheConfiguration.store(approvedFolders: [fixture.npm], userHome: fixture.home, npmContinuation: cursor)
        expectRejected(replaced)
        #expect(replaced.npmDiscovery?.scopeID != first.npmDiscovery?.scopeID)
    }

    @Test("Ordinary install activity changing directory times does not invalidate continuation")
    func mutableDirectoryTimesAreNotIdentity() throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        for index in 0..<300 { _ = try fixture.bucket(index) }
        let first = CacheConfiguration.store(approvedFolders: [fixture.npm], userHome: fixture.home)
        let cursor = try #require(first.npmDiscovery?.nextCursor)
        try Data("new install metadata".utf8).write(to: fixture.npm.appendingPathComponent("install-state"))
        let next = CacheConfiguration.store(approvedFolders: [fixture.npm], userHome: fixture.home, npmContinuation: cursor)
        #expect(next.npmDiscovery?.scopeID == first.npmDiscovery?.scopeID)
        #expect(!next.inspectionIssues.contains { $0.message.contains("does not match") })
        #expect(!npmRoots(next).isEmpty)
        #expect(Set(npmRoots(first).map(\.id)).isDisjoint(with: Set(npmRoots(next).map(\.id))))
    }

    @Test("Exact bucket approval completes without reading an unreadable sibling parent")
    func exactGrantNeverWalksSiblings() throws {
        let fixture = try NPMContinuationFixture()
        let approved = try fixture.bucket(0xaabb)
        let prefix = approved.deletingLastPathComponent()
        defer {
            _ = chmod(prefix.path, 0o755)
            fixture.remove()
        }
        for index in 0..<256 where index != 0xbb {
            _ = try fixture.bucket(0xaa00 + index)
        }
        #expect(chmod(prefix.path, 0o111) == 0)
        // O_SEARCH ancestor traversal remains possible; listing the parent is not.
        if getuid() != 0 {
            let control = open(prefix.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            if control >= 0 { close(control) }
            #expect(control < 0)
        }
        let config = CacheConfiguration.store(approvedFolders: [approved], userHome: fixture.home)
        #expect(npmRoots(config).map(\.url) == [approved])
        #expect(config.npmDiscovery?.inspectedBuckets == 1)
        #expect(config.npmDiscovery?.hasMore == false)
        #expect(config.npmDiscovery?.nextCursor == nil)
        #expect(config.roots.allSatisfy { $0.url.path == approved.path || $0.url.path.hasPrefix(approved.path + "/") })
        let recovery = CacheConfiguration.storeRecovery(approvedParentFolders: [approved], userHome: fixture.home)
        #expect(recovery.roots.map(\.url) == [approved])
        #expect(recovery.readAccessRoots == [approved])
        #expect(recovery.npmDiscovery == nil)
    }

    @Test("A first-prefix grant never discovers a sibling first-prefix range")
    func prefixGrantIsRangeBounded() throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        for second in 0..<256 { _ = try fixture.bucket(0x7f00 + second) }
        _ = try fixture.bucket(0x8000)
        let approved = fixture.bucketURL(0x7f00).deletingLastPathComponent()
        let result = try collect(fixture, approved: [approved])
        #expect(result.roots.count == 256)
        #expect(result.roots.allSatisfy { $0.url.deletingLastPathComponent() == approved })
        #expect(result.pages.last?.npmDiscovery?.hasMore == false)
    }

    @Test("Malformed cursors cannot promote objects or silently restart at the first page")
    func malformedCursorFailsClosed() throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        _ = try fixture.bucket(0)
        for cursor in ["not a cursor", String(repeating: "A", count: 2_049), Data("{}".utf8).base64EncodedString()] {
            expectRejected(CacheConfiguration.store(approvedFolders: [fixture.npm], userHome: fixture.home, npmContinuation: cursor))
        }
    }

    @Test("Cancellation never advertises a completed discovery or promotes a new cleanup root")
    func cancellationIsHonest() async throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        _ = try fixture.bucket(0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return CacheConfiguration.store(approvedFolders: [fixture.npm], userHome: fixture.home)
        }
        let cancelled = await task.value
        #expect(npmRoots(cancelled).isEmpty)
        #expect(cancelled.inspectionIssues.contains { $0.message.contains("cancelled") })
        #expect(cancelled.npmDiscovery == nil || cancelled.npmDiscovery?.hasMore == true)
    }

    @Test("A real later-page move survives relaunch and restores from only its exact approved parent")
    func laterPageReceiptRestoresIndependentlyOfDiscoveryPage() async throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        for index in 0..<300 { _ = try fixture.bucket(index) }
        let original = try fixture.lateContent()
        let originalBytes = try Data(contentsOf: original)
        let parent = original.deletingLastPathComponent()
        // Broad Home remains available as history/read context, but must not
        // collapse the later exact recovery parent back into discovery page one.
        let pages = try collect(fixture, approved: [fixture.home]).pages
        let laterPage = try #require(pages.first { npmRoots($0).contains { $0.url == parent } })
        #expect(!npmRoots(pages[0]).contains { $0.url == parent })
        let trash = try fixture.directory(".Trash")
        let activity = fixture.home.appendingPathComponent("receipts", isDirectory: true)
        let mover: @Sendable (URL) throws -> URL = { source in
            let target = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: target)
            return target
        }
        let scanningEngine = CacheEngine(configuration: laterPage, activityDirectory: activity,
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: mover)
        let scan = await scanningEngine.scan()
        let candidate = try #require(scan.eligibleEntries.first { $0.url == original })
        #expect(try await scanningEngine.authorizationLocations(entryIDs: [candidate.id]) == [parent])
        let receipt = await scanningEngine.clean(entryIDs: [candidate.id])
        #expect(receipt.trashedCount == 1)
        #expect(receipt.issues.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        let exactTrash = try #require(receipt.items.first?.trashURL)
        #expect(try Data(contentsOf: exactTrash) == originalBytes)

        let historyConfig = CacheConfiguration.store(approvedFolders: [fixture.home], userHome: fixture.home)
        #expect(!npmRoots(historyConfig).contains { $0.url == parent })
        let relaunchedHistory = CacheEngine(configuration: historyConfig, activityDirectory: activity,
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: mover)
        #expect(await relaunchedHistory.history().contains { $0.id == receipt.id && $0.canRestore })

        // The native review supplies exactly this parent. Core tests exercise
        // the authorization boundary without creating real system file grants.
        let recoveryConfig = CacheConfiguration.storeRecovery(approvedParentFolders: [parent], userHome: fixture.home)
        #expect(recoveryConfig.roots.map(\.url) == [parent])
        #expect(recoveryConfig.readAccessRoots == [parent])
        #expect(recoveryConfig.npmDiscovery == nil)
        #expect(recoveryConfig.roots.first?.id == receipt.items.first?.rootID)
        let recovery = CacheEngine(configuration: recoveryConfig, activityDirectory: activity,
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: mover)
        #expect(try await recovery.restoreAuthorizationLocations(receiptID: receipt.id) == [parent])
        let restored = await recovery.restore(receiptID: receipt.id, approvedTrashItems: [exactTrash])
        #expect(restored.restoredCount == 1, "\(restored.issues.map(\.message))")
        #expect(restored.issues.isEmpty)
        let returnedBytes = try Data(contentsOf: original)
        #expect(returnedBytes == originalBytes)
        #expect(SHA512.hash(data: returnedBytes) == SHA512.hash(data: originalBytes))
        #expect(!FileManager.default.fileExists(atPath: exactTrash.path))
        let finalEngine = CacheEngine(configuration: recoveryConfig, activityDirectory: activity,
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: mover)
        #expect(await finalEngine.history().first { $0.id == receipt.id }?.items.first?.status == .restored)
    }

    @Test("Recovery retains more than 32 exact bucket approvals and rejects broad or wrong-home paths")
    func recoveryReconstructsOnlyExactPhysicalParents() throws {
        let fixture = try NPMContinuationFixture()
        defer { fixture.remove() }
        let parents = try (0..<40).map { try fixture.bucket($0) }
        let broadAndExact = CacheConfiguration.storeRecovery(
            approvedParentFolders: [fixture.home, fixture.npm] + parents + [parents[0]], userHome: fixture.home)
        #expect(broadAndExact.roots.count == 40)
        #expect(Set(broadAndExact.readAccessRoots ?? []) == Set(parents))
        #expect(broadAndExact.roots.allSatisfy { $0.contentValidation == .npmSHA512 && $0.minimumAge == NPMContentPolicy.minimumAge })
        #expect(broadAndExact.npmDiscovery == nil)
        #expect(broadAndExact.inspectionIssues.count == 2)
        let wrongHome = try fixture.directory("container/Data")
        #expect(CacheConfiguration.storeRecovery(approvedParentFolders: parents, userHome: wrongHome).roots.isEmpty)
        let alias = fixture.home.appendingPathComponent("bucket-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parents[0])
        #expect(CacheConfiguration.storeRecovery(approvedParentFolders: [alias], userHome: fixture.home).roots.isEmpty)
        #expect(chmod(parents[0].path, 0o777) == 0)
        #expect(CacheConfiguration.storeRecovery(approvedParentFolders: [parents[0]], userHome: fixture.home).roots.isEmpty)
        #expect(CacheConfiguration.storeRecovery(approvedParentFolders: [fixture.home], userHome: fixture.home).roots.isEmpty)
    }

    private func collect(_ fixture: NPMContinuationFixture, approved: [URL]) throws -> (roots: [CacheRoot], pages: [CacheConfiguration]) {
        var cursor: String?
        var scopeID: String?
        var roots: [CacheRoot] = []
        var pages: [CacheConfiguration] = []
        var seen: Set<String> = []
        for _ in 0..<100 {
            let config = CacheConfiguration.store(approvedFolders: approved, userHome: fixture.home, npmContinuation: cursor)
            let coverage = try #require(config.npmDiscovery)
            let current = npmRoots(config)
            #expect((0...256).contains(coverage.inspectedBuckets))
            #expect(current.count == coverage.inspectedBuckets)
            #expect(current.allSatisfy { !seen.contains($0.url.path) })
            if let scopeID { #expect(coverage.scopeID == scopeID) } else { scopeID = coverage.scopeID }
            current.forEach { seen.insert($0.url.path) }
            roots.append(contentsOf: current)
            pages.append(config)
            if !coverage.hasMore {
                #expect(coverage.nextCursor == nil)
                return (roots, pages)
            }
            let next = try #require(coverage.nextCursor)
            #expect(next != cursor)
            cursor = next
        }
        throw NPMContinuationFixtureError.didNotFinish
    }

    private func expectRejected(_ config: CacheConfiguration) {
        #expect(npmRoots(config).isEmpty)
        #expect(config.npmDiscovery?.inspectedBuckets == 0)
        #expect(config.npmDiscovery?.hasMore == false)
        #expect(config.npmDiscovery?.nextCursor == nil)
        #expect(config.inspectionIssues.contains { $0.message.contains("continuation does not match") })
    }

    private func npmRoots(_ config: CacheConfiguration) -> [CacheRoot] {
        config.roots.filter { $0.contentValidation == .npmSHA512 }
    }
}

private enum NPMContinuationFixtureError: Error { case didNotFinish, missingDigest }
private struct NPMContinuationFixture: Sendable {
    let home: URL
    let contentBytes = Data("later valid npm download".utf8)
    var npm: URL { home.appendingPathComponent(".npm", isDirectory: true) }
    init() throws {
        home = URL(fileURLWithPath: "/private/tmp/RoomNPMContinuation-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
    }
    func directory(_ path: String) throws -> URL {
        let result = home.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }
    func bucketURL(_ index: Int) -> URL {
        npm.appendingPathComponent("_cacache/content-v2/sha512/" + String(format: "%02x/%02x", index / 256, index % 256), isDirectory: true)
    }
    func bucket(_ index: Int) throws -> URL {
        let url = bucketURL(index)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func lateContent() throws -> URL {
        // Pick a true addressed payload beyond the first 300 low-prefix buckets.
        for nonce in 0..<1_000 {
            let bytes = nonce == 0 ? contentBytes : Data("later valid npm download \(nonce)".utf8)
            let digest = SHA512.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard let index = Int(digest.prefix(4), radix: 16), index >= 0x8000 else { continue }
            let url = try bucket(index).appendingPathComponent(String(digest.dropFirst(4)))
            try bytes.write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-40 * 86_400)], ofItemAtPath: url.path)
            return url
        }
        throw NPMContinuationFixtureError.missingDigest
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
#endif
