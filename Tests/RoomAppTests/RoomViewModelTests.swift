import Foundation
@testable import RoomCore
import Testing
@testable import RoomApp

@Suite @MainActor
struct RoomViewModelTests {
    @Test func foundSpaceAndEligibleSelectionStayDistinct() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        #expect(model.sources.count == 1)
        #expect(source.bytes > source.eligibleBytes)
        #expect(source.eligibleBytes > 0)
        #expect(model.totalBytes == source.bytes)
        #expect(model.selectedBytes == source.eligibleBytes)
        #expect(model.selection == [source.id])

        model.clearSelection()
        #expect(model.selectedBytes == 0)
        #expect(model.totalBytes == source.bytes)
        model.toggleSelection(id: source.id)
        #expect(model.selectedBytes == source.eligibleBytes)
        model.toggleSelection(id: "not-a-scanned-source")
        #expect(model.selectedBytes == source.eligibleBytes)
    }

    @Test func sourcePathsAndProtectedSizesComeFromTheActualScan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        #expect(model.sources.first?.name == "Codex")
        #expect(model.sources.first?.path == fixture.cache.path)
        let protected = try #require(model.protectedSources.first)
        #expect(protected.path == fixture.protected.path)
        #expect(protected.bytes > 0)
        #expect(model.sources.allSatisfy { !$0.path.contains(fixture.protected.lastPathComponent) })
        #expect(model.scanIssues.isEmpty)
        #expect(model.lastScanned != nil)
    }

    @Test func cancelledRescanKeepsMeasurementsWithoutAllowingCleanup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let previousID = try #require(model.sources.first?.id)
        #expect(!model.selection.isEmpty)

        model.scan()
        model.cancelScan()
        try await waitForScan(model)
        #expect(!model.sources.isEmpty)
        #expect(model.selection.isEmpty)
        #expect(model.lastScanned == nil)
        #expect(model.isPartialScan)
        #expect(model.clearableBytes == 0)
        #expect(model.canScan)
        #expect(!model.canReviewCleanup)
        model.toggleSelection(id: previousID)
        model.selectRecommended()
        #expect(model.selection.isEmpty)
        #expect(model.statusMessage?.contains("Scan stopped") == true)
    }

    @Test func scanActionDoesNotDependOnCleanupSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        #expect(model.scanScope == .full)
        #expect(model.canScan)
        #expect(!model.canReviewCleanup)
        model.scan()
        #expect(model.isScanning)
        #expect(model.canScan) // Same control must remain usable as Stop.
        try await waitForScan(model)
        #expect(model.canReviewCleanup)
        model.clearSelection()
        #expect(model.canScan)
        #expect(!model.canReviewCleanup)
        #expect(model.clearableBytes > 0)
        #expect(model.heldBytes > 0)
    }

    #if !ROOM_APP_STORE
    @Test func changingScanScopeKeepsHistoryAndRestoresTheOriginalCatalogue() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let activity = fixture.directory.appendingPathComponent("activity", isDirectory: true)
        let trash = fixture.directory.appendingPathComponent("fixture-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let engine = CacheEngine(configuration: fixture.configuration, activityDirectory: activity,
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: { original in
                let destination = trash.appendingPathComponent(original.lastPathComponent)
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            })
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        let model = RoomViewModel(engine: engine)
        await model.refreshHistory()
        #expect(model.activity.first?.id == receipt.id)
        model.setScanScope(.quick)
        await model.refreshHistory()
        let record = try #require(model.activity.first)
        #expect(record.id == receipt.id)
        await model.restore(record: record)
        // The post-restore rescan belongs to the newly selected production scope.
        // Stop it before it measures anything; this test uses isolated files only.
        model.cancelScan()
        try await waitForScan(model)
        #expect(model.errorMessage == nil)
        #expect(model.activity.first?.restoredCount == 1)
        #expect(try Data(contentsOf: fixture.cache.appendingPathComponent("old-cache")) == Data(repeating: 0x51, count: 32_768))
        #expect(!FileManager.default.fileExists(atPath: trash.appendingPathComponent("old-cache").path))
    }

    #endif

    @Test func packageManagersKeepIndependentReviewSelections() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let yarnCache = fixture.directory.appendingPathComponent("yarn-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: yarnCache, withIntermediateDirectories: true)
        let yarnFile = yarnCache.appendingPathComponent("old-download")
        try Data(repeating: 0x54, count: 16_384).write(to: yarnFile)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: yarnFile.path)
        let configuration = CacheConfiguration(roots: [
            CacheRoot(id: "npm", title: "npm", subtitle: "Downloads", symbol: "shippingbox", category: "developer",
                url: fixture.cache, consequence: "Downloaded packages"),
            CacheRoot(id: "yarn", title: "Yarn", subtitle: "Downloads", symbol: "shippingbox", category: "developer",
                url: yarnCache, consequence: "Downloaded packages")
        ], homeDirectory: fixture.directory)
        let model = RoomViewModel(engine: CacheEngine(configuration: configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let npm = try #require(model.sources.first { $0.id == "npm" })
        let yarn = try #require(model.sources.first { $0.id == "yarn" })
        #expect(model.sources.count == 2)
        #expect(npm.name == "npm")
        #expect(yarn.name == "Yarn")
        #expect(model.selectedBytes == npm.eligibleBytes + yarn.eligibleBytes)
        model.toggleSelection(id: npm.id)
        #expect(model.selectedBytes == yarn.eligibleBytes)
        #expect(model.selection == [yarn.id])
    }

    @Test func managedStorageIsClearlyReportedWithoutCleanupSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reason = "Container images and volumes are managed by their owning tool. Inspect only."
        let configuration = CacheConfiguration(roots: [
            CacheRoot(id: "docker-disk", title: "Docker storage", subtitle: "Managed data", symbol: "externaldrive",
                category: "developer", url: fixture.cache, consequence: reason, cleanupPolicy: .inspectOnly(reason))
        ], homeDirectory: fixture.directory)
        let model = RoomViewModel(engine: CacheEngine(configuration: configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        #expect(source.isInspectionOnly)
        #expect(source.name == "Docker storage")
        #expect(source.subtitle.contains("inspect only"))
        #expect(source.bytes > 0)
        #expect(source.eligibleBytes == 0)
        #expect(!source.isAvailable)
        #expect(model.selection.isEmpty)
        #expect(!model.canReviewCleanup)
        #expect(!source.notes.contains("Only unchanged cache items older than seven days"))
    }

    private func waitForScan(_ model: RoomViewModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.isScanning && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isScanning)
    }
}

private struct Fixture {
    let directory: URL
    let cache: URL
    let protected: URL
    let configuration: CacheConfiguration

    init() throws {
        let root = URL(fileURLWithPath: "/private/tmp/RoomViewModelTests-\(UUID().uuidString)", isDirectory: true)
        directory = root
        cache = root.appendingPathComponent("cache", isDirectory: true)
        protected = root.appendingPathComponent("protected-history", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        let old = cache.appendingPathComponent("old-cache")
        try Data(repeating: 0x51, count: 32_768).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: old.path)
        try Data(repeating: 0x52, count: 65_536).write(to: cache.appendingPathComponent("recent-cache"))
        try Data(repeating: 0x53, count: 16_384).write(to: protected.appendingPathComponent("session"))
        configuration = CacheConfiguration(roots: [
            CacheRoot(id: "codex-fixture", title: "Fixture source", subtitle: "Fixture data", symbol: "terminal",
                category: "agents", url: cache, consequence: "Rebuildable test cache.")
        ], protectedLocations: [
            ProtectedLocation(id: "history", title: "Protected history", url: protected, reason: "User data")
        ], homeDirectory: root)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
