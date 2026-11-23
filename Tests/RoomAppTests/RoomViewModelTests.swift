import Foundation
@testable import RoomCore
import Testing
@testable import RoomApp

@Suite @MainActor
struct RoomViewModelTests {
    @Test func reviewDeselectsAPartialSourceWhileTheGridCanSelectAll() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.addOldCache(named: "second-cache")
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore)
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        let items = model.cleanupCandidates(for: source.id)
        try #require(items.count == 2)

        model.toggleEntrySelection(id: items[1].id, sourceID: source.id)
        #expect(model.selectedEntryIDs == [items[0].id] && model.partiallySelectedSource(source.id))
        model.setSelection(id: source.id, selected: false)
        #expect(model.selection.isEmpty && model.selectedEntryIDs.isEmpty && model.selectedBytes == 0)
        #expect(!model.canReviewCleanup)

        model.setSelection(id: source.id, selected: true)
        #expect(model.selectedEntryIDs == Set(items.map(\.id)))
        model.toggleEntrySelection(id: items[1].id, sourceID: source.id)
        model.toggleSelection(id: source.id)
        #expect(model.selectedEntryIDs == Set(items.map(\.id)))
    }

    @Test func eligibleItemsCanBeSelectedIndividuallyAndCannotSurviveARescan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let second = try fixture.addOldCache(named: "second-cache")
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore)
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        let candidates = model.cleanupCandidates(for: source.id)
        #expect(Set(candidates.map(\.name)) == ["old-cache", "second-cache"])
        #expect(model.source(containing: fixture.cache.appendingPathComponent("recent-cache").path)?.id == source.id)
        #expect(model.source(containing: fixture.cache.path + "-different/file") == nil)
        let excluded = try #require(candidates.first { $0.url.path == second.path })
        model.toggleEntrySelection(id: excluded.id, sourceID: source.id)
        #expect(model.partiallySelectedSource(source.id))
        #expect(model.selection == [source.id])
        #expect(model.selectedBytes == source.eligibleBytes - excluded.bytes)
        #expect(!model.selectedEntryIDs.contains(excluded.id))
        #expect(model.cleanupRows.first?.entryIDs == model.selectedEntryIDs)
        #expect(model.cleanupRows.first?.selectedBytes == model.selectedBytes)

        model.scan()
        #expect(model.cleanupCandidates(for: source.id).isEmpty)
        #expect(model.selectedEntryIDs.isEmpty)
        try await waitForScan(model)
        let picked = model.selectedEntryIDs
        model.toggleEntrySelection(id: excluded.id, sourceID: source.id)
        #expect(!picked.isEmpty && model.selectedEntryIDs == picked)
        #expect(!model.partiallySelectedSource(source.id))
    }

    @Test func diskMapReviewUsesExactEligiblePathsAndExpiresOnRescan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = fixture.cache.appendingPathComponent("old-cache")
        let sibling = try fixture.addOldCache(named: "old-cache-other")
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore)

        #expect(model.mapCleanupAction(at: target) == .check)
        model.scan()
        #expect(model.mapCleanupAction(at: target) == .checking)
        try await waitForScan(model)
        #expect(model.mapCleanupAction(at: target) == .review)
        #expect(model.mapCleanupAction(at: fixture.protected) == .empty)
        #expect(model.makeMapCleanup(at: fixture.cache.appendingPathComponent("recent-cache")) == nil)
        #expect(model.mapCleanupAction(at: fixture.cache, includesContents: false) == nil)
        #expect(model.makeMapCleanup(at: fixture.cache, includesContents: false) == nil)

        let request = try #require(model.makeMapCleanup(at: target, includesContents: false))
        #expect(request.rows.map(\.location) == [target.path])
        let targetIDs = try #require(request.rows.first).entryIDs
        let other = try #require(model.makeMapCleanup(at: sibling))
        let otherIDs = try #require(other.rows.first).entryIDs
        #expect(model.canCleanMapSelection(request, entryIDs: targetIDs))
        #expect(!model.canCleanMapSelection(request, entryIDs: targetIDs.union(otherIDs)))
        let mismatched = RoomMapCleanup(location: target, reportID: request.reportID, rows: other.rows)
        #expect(!model.canCleanMapSelection(mismatched, entryIDs: otherIDs))
        #expect(model.selectedEntryIDs == targetIDs.union(otherIDs))

        model.scan()
        try await waitForScan(model)
        #expect(!model.canCleanMapSelection(request, entryIDs: targetIDs))
    }

    #if !ROOM_APP_STORE
    @Test func diskMapCleanupMovesOnlyReviewedItemsAndKeepsOtherCacheSelections() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let unselected = try fixture.addOldCache(named: "unselected-cache")
        let original = fixture.cache.appendingPathComponent("old-cache")
        let trash = fixture.directory.appendingPathComponent("fixture-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        let engine = CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity"), processProvider: { [] },
            fixtureTrashDirectory: trash, trashProvider: { item in
                let destination = trash.appendingPathComponent(item.lastPathComponent)
                try FileManager.default.moveItem(at: item, to: destination)
                return destination
            })
        let model = RoomViewModel(engine: engine, cachesCheckStore: fixture.cachesCheckStore)
        model.scan()
        try await waitForScan(model)

        let review = try #require(model.makeMapCleanup(at: fixture.cache))
        let selected = try #require(review.rows.first { $0.location == original.path }).entryIDs
        let retained = try #require(review.rows.first { $0.location == unselected.path }).entryIDs
        await model.cleanMapSelection(review, entryIDs: selected)

        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: unselected.path))
        #expect(FileManager.default.fileExists(atPath: fixture.protected.appendingPathComponent("session").path))
        #expect(model.selectedEntryIDs == retained)
        #expect(model.movedReceipt?.details.map(\.name) == ["old-cache"])
        #expect(!model.canCleanMapSelection(review, entryIDs: selected))
    }

    @Test func onlySelectedItemsMoveAndRestoreDoesNotRescan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let excluded = try fixture.addOldCache(named: "kept-by-choice")
        let trash = fixture.directory.appendingPathComponent("fixture-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        let engine = CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity"), processProvider: { [] },
            fixtureTrashDirectory: trash, trashProvider: { original in
                let destination = trash.appendingPathComponent(original.lastPathComponent)
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            })
        let model = RoomViewModel(engine: engine, cachesCheckStore: fixture.cachesCheckStore)
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        let item = try #require(model.cleanupCandidates(for: source.id).first { $0.url.path == excluded.path })
        model.toggleEntrySelection(id: item.id, sourceID: source.id)
        await model.cleanSelected()
        #expect(!model.isScanning)
        let retained = fixture.cache.appendingPathComponent("recent-cache")
        #expect(FileManager.default.fileExists(atPath: excluded.path))
        #expect(FileManager.default.fileExists(atPath: retained.path))
        let record = try #require(model.activity.first)
        #expect(record.itemCount == 1 && record.details.first?.name == "old-cache")
        await model.restore(record: record)
        #expect(!model.isScanning && model.selectedEntryIDs.isEmpty)
        #expect(model.activity.first?.restoredCount == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.cache.appendingPathComponent("old-cache").path))
    }
    #endif

    @Test func foundSpaceAndEligibleSelectionStayDistinct() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore)
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
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore)
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
        let activity = RoomActivityCenter()
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore,
            activityCenter: activity)
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
        if case .stopped = activity.visible {} else { Issue.record("The Activity pill should show the stopped check.") }
    }

    @Test func scanActionDoesNotDependOnCleanupSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore)
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
        let model = RoomViewModel(engine: engine, cachesCheckStore: fixture.cachesCheckStore)
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
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore)
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
            activityDirectory: fixture.directory.appendingPathComponent("activity")), cachesCheckStore: fixture.cachesCheckStore)
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

    @MainActor var cachesCheckStore: RoomCachesCheckStore {
        RoomCachesCheckStore(defaults: UserDefaults(suiteName: directory.lastPathComponent)!)
    }

    func addOldCache(named name: String) throws -> URL {
        let item = cache.appendingPathComponent(name)
        try Data(repeating: 0x56, count: 32_768).write(to: item)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: item.path)
        return item
    }

    func remove() {
        UserDefaults(suiteName: directory.lastPathComponent)?.removePersistentDomain(forName: directory.lastPathComponent)
        try? FileManager.default.removeItem(at: directory)
    }
}
