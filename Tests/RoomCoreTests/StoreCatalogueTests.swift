import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Explicit Store scan boundaries")
struct StoreCatalogueTests {
    @Test("No approvals create no source or implicit home/process inspection")
    func emptyApproval() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let config = CacheConfiguration.store(approvedFolders: [], userHome: fixture.home)
        #expect(config.roots.isEmpty && config.protectedLocations.isEmpty)
        #expect(config.readAccessRoots == [])
        let calls = Mutex(0)
        let engine = CacheEngine(configurationProvider: { config }, activityDirectory: fixture.url("receipts"),
            processProvider: { calls.withLock { $0 += 1 }; return [] }, trashHomeDirectory: fixture.home)
        let report = await engine.scan()
        #expect(report.groups.isEmpty && report.protectedData.isEmpty)
        #expect(report.volume.totalBytes == 0 && report.volume.availableBytes == 0)
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("Known roots are confined to physical approved paths with component boundaries")
    func approvedRootBoundary() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let approved = try fixture.directory("Library/Caches")
        let inside = try fixture.write("Library/Caches/Homebrew/archive", "inside")
        let outside = try fixture.write(".gradle/caches/archive", "keep outside")
        let config = CacheConfiguration.store(approvedFolders: [approved], userHome: fixture.home)
        #expect(config.roots.contains { $0.id == "homebrew" })
        #expect(!config.roots.contains { $0.id == "gradle" })
        #expect(config.roots.allSatisfy { $0.url.path == approved.path || $0.url.path.hasPrefix(approved.path + "/") })
        let engine = fixture.engine(config)
        let report = await engine.scan()
        #expect(report.groups.allSatisfy { $0.rootURL.path == approved.path || $0.rootURL.path.hasPrefix(approved.path + "/") })
        #expect(report.groups.flatMap(\.entries).contains { $0.url == inside })
        #expect(!report.groups.flatMap(\.entries).contains { $0.url == outside })
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep outside")
    }

    @Test("Unknown selections, descendants of known roots, and lookalike cache paths stay inspect-only")
    func unknownSelection() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let unknown = try fixture.directory("Documents/Cache")
        _ = try fixture.write("Documents/Cache/keep", "user work")
        let lookalike = try fixture.directory("Library/Caches-old/Homebrew")
        _ = try fixture.write("Library/Caches-old/Homebrew/keep", "user work")
        let partialKnown = try fixture.directory(".gradle/caches/modules-2")
        _ = try fixture.write(".gradle/caches/modules-2/keep", "user work")
        let config = CacheConfiguration.store(approvedFolders: [unknown, lookalike, partialKnown], userHome: fixture.home)
        #expect(config.roots.count == 3)
        #expect(config.roots.allSatisfy { if case .inspectOnly = $0.cleanupPolicy { return true }; return false })
        #expect(await fixture.engine(config).scan().eligibleEntries.isEmpty)
    }

    @Test("Linked approved roots and linked ancestors cannot redirect a Store scan")
    func symlinksAndInvalidRoots() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let external = try fixture.directory("external")
        let link = fixture.url("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        let nested = external.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let config = CacheConfiguration.store(approvedFolders: [link, link.appendingPathComponent("Caches")], userHome: fixture.home)
        #expect(config.roots.isEmpty)
        #expect(config.inspectionIssues.count == 2)
        let root = CacheConfiguration.store(approvedFolders: [fixture.home], userHome: URL(fileURLWithPath: "/"))
        #expect(root.roots.isEmpty)
        let remote = CacheConfiguration.store(approvedFolders: [URL(string: "https://example.com/cache")!], userHome: fixture.home)
        #expect(remote.roots.isEmpty && !remote.inspectionIssues.isEmpty)
    }

    @Test("A sandbox container or unrelated home cannot promote a real selected folder to a known cache")
    func explicitHomeIsNotGuessed() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let realCache = try fixture.directory("Library/Caches/Homebrew")
        let wrongHome = try fixture.directory("Library/Containers/com.example.store/Data")
        let config = CacheConfiguration.store(approvedFolders: [realCache], userHome: wrongHome)
        #expect(config.homeDirectory == wrongHome)
        #expect(!config.roots.contains { $0.id == "homebrew" })
        #expect(config.roots.count == 1)
        #expect(config.roots.allSatisfy { if case .inspectOnly = $0.cleanupPolicy { return true }; return false })
    }

    @Test("Nested approvals do not count known or unknown allocations twice")
    func overlapAndSentinel() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let parent = try fixture.directory("Library/Caches/org.swift.swiftpm")
        let prebuilt = try fixture.write("Library/Caches/org.swift.swiftpm/prebuilts/swift-syntax/archive", "generated")
        let sentinel = try fixture.write("Library/Caches/org.swift.swiftpm/prebuilts/noprebuilts", "preference")
        let config = CacheConfiguration.store(approvedFolders: [parent, prebuilt.deletingLastPathComponent(), parent], userHome: fixture.home)
        #expect(config.readAccessRoots?.count == 1)
        #expect(config.roots.contains { $0.id == "swiftpm-prebuilts" })
        #expect(!config.roots.contains { if case .allowed = $0.cleanupPolicy { return $0.url.path == sentinel.path || $0.url.path == sentinel.deletingLastPathComponent().path }; return false })
        let report = await fixture.engine(config).scan()
        let entries = report.groups.flatMap(\.entries)
        #expect(entries.contains { $0.url == prebuilt })
        #expect(report.groups.filter { $0.isInspectionOnly == true }.flatMap(\.entries).contains { $0.url.path == sentinel.deletingLastPathComponent().path })
        #expect(report.eligibleEntries.allSatisfy { !$0.url.path.contains("noprebuilts") })
    }

    @Test("Permission review derives exact parents only from current minted candidates")
    func authorizationLocations() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let cache = try fixture.directory("Library/Caches/Homebrew")
        _ = try fixture.write("Library/Caches/Homebrew/archive", "old cache")
        let config = CacheConfiguration.store(approvedFolders: [cache], userHome: fixture.home)
        let engine = fixture.engine(config)
        let report = await engine.scan()
        let ids = report.eligibleEntries.map(\.id)
        #expect(!ids.isEmpty)
        #expect(try await engine.authorizationLocations(entryIDs: ids).map(\.path) == [cache.path])
        await #expect(throws: (any Error).self) { try await engine.authorizationLocations(entryIDs: [UUID()]) }
        _ = await engine.scan()
        await #expect(throws: (any Error).self) { try await engine.authorizationLocations(entryIDs: ids) }
    }
}

#if ROOM_APP_STORE
@Suite("Store analysis executes no external runtime")
struct StoreAnalysisRuntimeTests {
    @Test("Store defaults hold guarded caches without pretending a successful ps result proves CLI visibility")
    func unverifiedToolVisibilityStaysHeld() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let cache = try fixture.directory("Library/Caches/Homebrew")
        _ = try fixture.write("Library/Caches/Homebrew/archive", "owned old cache")
        let config = CacheConfiguration.store(approvedFolders: [cache], userHome: fixture.home)
        let engine = CacheEngine(configurationProvider: { config }, activityDirectory: fixture.url("receipts"),
            trashHomeDirectory: fixture.home)
        let report = await engine.scan()
        #expect(!report.groups.isEmpty)
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.issues.contains { $0.message.contains("App Store sandbox") })
    }

    @Test("The Store build cannot discover or start an external local-model worker")
    func noExternalRuntime() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/RoomStore-NoRuntime-" + UUID().uuidString, isDirectory: true)
        #expect(!StorageAIEngine.supportsExternalLocalRuntime)
        let runtime = LocalModelRuntime(home: root)
        #expect(!(await runtime.availability()).isAvailable)
        await #expect(throws: LocalModelFailure.self) { try await runtime.generate([]) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("Store recovery retains exact-item scope and requires exact fallback approval when that scope is missing")
    func exactTrashBookmarkAndFallback() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let cache = try fixture.directory("Library/Caches/Homebrew")
        let original = try fixture.write("Library/Caches/Homebrew/archive", "fixture bytes remain identical")
        let trash = try fixture.directory("fixture-trash")
        let activity = fixture.url("receipts")
        let config = CacheConfiguration.store(approvedFolders: [cache], userHome: fixture.home)
        let mover: @Sendable (URL) throws -> URL = { source in
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        let engine = CacheEngine(configuration: config, activityDirectory: activity,
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: mover)
        let scan = await engine.scan()
        var receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        #expect(receipt.issues.isEmpty)
        #expect(receipt.items.first?.trashAccessBookmark != nil)
        let exact = try #require(receipt.items.first?.trashURL)
        receipt.items[0].trashAccessBookmark = nil
        try JSONEncoder().encode(receipt).write(to: activity.appendingPathComponent(receipt.id.uuidString + ".json"), options: .atomic)
        let recovery = CacheEngine(configuration: config, activityDirectory: activity,
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: mover)
        #expect(try await recovery.restoreAuthorizationLocations(receiptID: receipt.id).map(\.path) == [cache.path])
        #expect(try await recovery.restoreTrashAuthorizationLocations(receiptID: receipt.id).map(\.path) == [exact.path])
        #expect(await recovery.restore(receiptID: receipt.id).restoredCount == 0)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        let restored = await recovery.restore(receiptID: receipt.id, approvedTrashItems: [exact])
        #expect(restored.restoredCount == 1)
        #expect(try String(contentsOf: original, encoding: .utf8) == "fixture bytes remain identical")
    }

    @Test("Trash approval preflight works after original-folder read access is removed")
    func trashPreflightWithoutOriginalAccess() async throws {
        let fixture = try StoreFixture()
        let cache = try fixture.directory("Library/Caches/Homebrew")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cache.path)
            fixture.remove()
        }
        _ = try fixture.write("Library/Caches/Homebrew/archive", "owned fixture")
        let trash = try fixture.directory(".Trash")
        let activity = fixture.url("receipts")
        let config = CacheConfiguration.store(approvedFolders: [cache], userHome: fixture.home)
        let engine = CacheEngine(configuration: config, activityDirectory: activity, processProvider: { [] },
            fixtureTrashDirectory: trash, trashProvider: { source in
                let destination = trash.appendingPathComponent(UUID().uuidString)
                try FileManager.default.moveItem(at: source, to: destination)
                return destination
            })
        let scan = await engine.scan()
        var receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        let exact = try #require(receipt.items.first?.trashURL)
        receipt.items[0].trashAccessBookmark = nil
        let receiptURL = activity.appendingPathComponent(receipt.id.uuidString + ".json")
        try JSONEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
        let before = try Data(contentsOf: receiptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: cache.path)
        let empty = CacheConfiguration.store(approvedFolders: [], userHome: fixture.home)
        let recovery = CacheEngine(configurationProvider: { empty }, activityDirectory: activity,
            processProvider: { [] }, trashHomeDirectory: fixture.home)
        #expect(try await recovery.restoreTrashAuthorizationLocations(receiptID: receipt.id).map(\.path) == [exact.path])
        #expect(try Data(contentsOf: receiptURL) == before)
    }
}
#endif

private struct StoreFixture: Sendable {
    let home: URL
    init() throws {
        home = URL(fileURLWithPath: "/private/tmp/RoomStore-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
    }
    func url(_ path: String) -> URL { home.appendingPathComponent(path) }
    func directory(_ path: String) throws -> URL {
        let value = url(path)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }
    func write(_ path: String, _ text: String) throws -> URL {
        let value = url(path)
        _ = try directory(value.deletingLastPathComponent().path.replacingOccurrences(of: home.path + "/", with: ""))
        try Data(text.utf8).write(to: value)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-40 * 86_400)], ofItemAtPath: value.path)
        return value
    }
    func engine(_ config: CacheConfiguration) -> CacheEngine {
        CacheEngine(configuration: config, activityDirectory: url("receipts"), processProvider: { [] }, fixtureTrashDirectory: url("fixture-trash"))
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
