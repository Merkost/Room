import Foundation
import Synchronization
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

    @Test func cancelledRescanDoesNotRelabelPreviousMeasurementsAsCurrent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let previousID = try #require(model.sources.first?.id)
        #expect(!model.selection.isEmpty)

        model.scan()
        // The previous completed amount must not be labeled as this scan's
        // measured-so-far value while the replacement is still preparing.
        #expect(model.sources.isEmpty)
        #expect(model.totalBytes == 0)
        model.cancelScan()
        try await waitForScan(model)
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

    @Test func individualEligibleUnitsCanBeExcludedWithoutSelectingHeldFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let another = fixture.cache.appendingPathComponent("another-old-cache")
        try Data(repeating: 0x41, count: 32_768).write(to: another)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: another.path)
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        let candidates = model.cleanupCandidates(for: source.id)
        #expect(candidates.count == 2)
        #expect(candidates.allSatisfy { !$0.path.contains("recent-cache") })
        let first = try #require(candidates.first)
        let original = model.selectedBytes
        let ids = model.selectedEntryIDs
        model.toggleEntrySelection(id: first.id, sourceID: source.id)
        #expect(model.selectedBytes == original - first.bytes)
        #expect(model.selectedCount(for: source.id) == 1)
        #expect(model.partiallySelectedSource(source.id))
        #expect(model.selectedEntryIDs == ids.subtracting([first.id]))
        #expect(model.canReviewCleanup)
        model.toggleEntrySelection(id: UUID(), sourceID: source.id)
        #expect(model.selectedEntryIDs == ids.subtracting([first.id]))
        model.clearSelection()
        model.toggleEntrySelection(id: first.id, sourceID: source.id)
        #expect(model.selectedEntryIDs == [first.id])
        #expect(model.selectedBytes == first.bytes)
        model.selectRecommended()
        #expect(model.selectedEntryIDs == ids)
        #expect(model.selectedBytes == original)
    }

    @Test func candidateSelectionsFollowTheAppliedReportAndClearDuringRescan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        let candidate = try #require(model.cleanupCandidates(for: source.id).first)
        #expect(model.isEntrySelected(candidate.id, sourceID: source.id))
        #expect(model.selectedCount(for: source.id) == 1)
        #expect(model.selectedBytes(for: source.id) == candidate.bytes)

        model.scan()
        #expect(model.cleanupCandidates(for: source.id).isEmpty)
        #expect(model.selectedEntryIDs.isEmpty)
        #expect(!model.isEntrySelected(candidate.id, sourceID: source.id))
        #expect(model.selectedCount(for: source.id) == 0)
        #expect(model.selectedBytes(for: source.id) == 0)
        try await waitForScan(model)
        let replacement = try #require(model.cleanupCandidates(for: source.id).first)
        #expect(replacement.id != candidate.id)
        #expect(replacement.path == candidate.path && replacement.bytes == candidate.bytes)
        #expect(!model.isEntrySelected(candidate.id, sourceID: source.id))
        #expect(model.isEntrySelected(replacement.id, sourceID: source.id))
        #expect(model.selectedEntryIDs == [replacement.id])
        #expect(model.selectedBytes == replacement.bytes)

        model.scan()
        model.cancelScan()
        try await waitForScan(model)
        #expect(model.isPartialScan)
        #expect(model.cleanupCandidates(for: source.id).isEmpty)
        #expect(model.selectedEntryIDs.isEmpty)
        #expect(!model.isEntrySelected(replacement.id, sourceID: source.id))
        #expect(model.selectedCount(for: source.id) == 0)
        #expect(model.selectedBytes(for: source.id) == 0)
    }

    #if ROOM_APP_STORE
    @Test func wrongFolderApprovalCanBeRetriedWithoutKeepingItsError() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = fixture.cache.appendingPathComponent("old-cache")
        let originalData = try Data(contentsOf: original)
        var selectedFolder = fixture.directory
        var pickerCalls = 0
        var retryStartedWithoutError = false
        var scopeStarts = 0
        var scopeEnds = 0
        weak var activeModel: RoomViewModel?
        let review = RoomStoreFolderReview(picker: { expected, allowsFiles in
            #expect(expected.path == fixture.cache.path && !allowsFiles)
            pickerCalls += 1
            if pickerCalls == 2 {
                retryStartedWithoutError = activeModel?.errorMessage == nil && activeModel?.isWorking == true
            }
            return selectedFolder
        }, beginScope: { _ in scopeStarts += 1; return true }, endScope: { _ in scopeEnds += 1 })
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity"), processProvider: { [] }), storeReview: review)
        activeModel = model
        defer { model.discardStoreReview() }
        model.scan()
        try await waitForScan(model)
        await model.prepareStoreCleanupReview()
        #expect(Set(model.storeReviewLocations.map(\.path)) == [fixture.cache.path])

        // The actual physical-identity check must reject a parent folder even
        // when the native picker seam reports that its security scope started.
        await model.allowStoreReviewLocation(fixture.cache)
        #expect(model.errorMessage == RoomStoreAccessError.exactFolderRequired.localizedDescription)
        #expect(model.storeGrantedPaths.isEmpty && !model.canRunStoreCleanup)
        #expect(scopeStarts == 1 && scopeEnds == 1)
        #expect(try Data(contentsOf: original) == originalData)

        selectedFolder = fixture.cache
        await model.allowStoreReviewLocation(fixture.cache)
        #expect(pickerCalls == 2 && retryStartedWithoutError)
        #expect(model.errorMessage == nil)
        #expect(model.storeGrantedPaths == [fixture.cache.path])
        #expect(model.storeAllLocationsGranted && model.canRunStoreCleanup)
        #expect(scopeStarts == 2 && scopeEnds == 1)
        #expect(try Data(contentsOf: original) == originalData)
        model.discardStoreReview()
        #expect(scopeStarts == scopeEnds)
    }

    @Test func equalByteItemReplacementRevokesWriteGrantsAndRequiresFreshReview() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = fixture.cache.appendingPathComponent("old-cache")
        let replacement = fixture.cache.appendingPathComponent("other-old-cache")
        let originalData = try Data(contentsOf: original)
        let replacementData = Data(repeating: 0x64, count: originalData.count)
        try replacementData.write(to: replacement)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: replacement.path)
        let trash = fixture.directory.appendingPathComponent("fixture-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        let moves = Mutex(0)
        let engine = CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity"), processProvider: { [] },
            fixtureTrashDirectory: trash, trashProvider: { url in
                moves.withLock { $0 += 1 }
                let destination = trash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            })
        var scopeStarts = 0
        var scopeEnds = 0
        let review = RoomStoreFolderReview(picker: { expected, allowsFiles in
            #expect(!allowsFiles && expected.path == fixture.cache.path)
            return expected
        }, beginScope: { _ in scopeStarts += 1; return true }, endScope: { _ in scopeEnds += 1 })
        let model = RoomViewModel(engine: engine, storeReview: review)
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        let candidates = model.cleanupCandidates(for: source.id)
        let first = try #require(candidates.first { $0.path == original.path })
        let second = try #require(candidates.first { $0.path == replacement.path })
        #expect(first.bytes > 0 && first.bytes == second.bytes)
        model.clearSelection()
        model.toggleEntrySelection(id: first.id, sourceID: source.id)
        await model.prepareStoreCleanupReview()
        #expect(Set(model.storeReviewLocations.map(\.path)) == [fixture.cache.path])
        #expect(!model.canRunStoreCleanup)
        await model.allowStoreReviewLocation(fixture.cache)
        #expect(model.canRunStoreCleanup && model.storeAllLocationsGranted)
        #expect(scopeStarts == 1 && scopeEnds == 0)
        let reviewedIDs = model.selectedEntryIDs
        let reviewedAmount = model.selectedBytes

        model.toggleEntrySelection(id: first.id, sourceID: source.id)
        model.toggleEntrySelection(id: second.id, sourceID: source.id)
        #expect(model.selectedBytes == reviewedAmount)
        #expect(model.selectedEntryIDs != reviewedIDs)
        #expect(model.selectedEntryIDs == [second.id])
        #expect(!model.canRunStoreCleanup && !model.storeAllLocationsGranted)
        #expect(model.storeReviewLocations.isEmpty && model.storeGrantedPaths.isEmpty)
        #expect(scopeStarts == scopeEnds)
        await model.cleanSelected()
        #expect(moves.withLock { $0 } == 0)
        #expect(try Data(contentsOf: original) == originalData)
        #expect(try Data(contentsOf: replacement) == replacementData)

        await model.prepareStoreCleanupReview()
        await model.allowStoreReviewLocation(fixture.cache)
        #expect(model.canRunStoreCleanup)
        await model.cleanSelected()
        try await waitForScan(model)
        #expect(model.selectedEntryIDs.isEmpty && model.selectedBytes == 0)
        #expect(model.selection.isEmpty)
        #expect(moves.withLock { $0 } == 1)
        #expect(try Data(contentsOf: original) == originalData)
        #expect(!FileManager.default.fileExists(atPath: replacement.path))
        #expect(try Data(contentsOf: trash.appendingPathComponent(replacement.lastPathComponent)) == replacementData)
        #expect(model.storeGrantedPaths.isEmpty && !model.canRunStoreCleanup)
        #expect(scopeStarts == 2 && scopeEnds == 2)
    }
    #endif

    @Test func changingNextScanScopeKeepsLabeledEvidenceButDisablesCleanup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let amount = model.totalBytes
        let measuredAt = model.lastScanned
        #expect(model.resultsScope == .full)
        model.setScanScope(.quick)
        #expect(model.totalBytes == amount)
        #expect(model.lastScanned == measuredAt)
        #expect(model.resultsScope == .full)
        #expect(model.isScopeChangePending)
        #expect(!model.canReviewCleanup)
        #expect(!model.canEditSelection)
        model.setScanScope(.full)
        #expect(!model.isScopeChangePending)
        #expect(model.canReviewCleanup)
    }

    @Test func diskHandoffFindsKnownSourceWithoutPromotingEligibility() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = RoomViewModel(engine: CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity")))
        model.scan()
        try await waitForScan(model)
        let ids = model.selectedEntryIDs
        #expect(model.source(containing: fixture.cache.appendingPathComponent("recent-cache").path)?.id == model.sources.first?.id)
        #expect(model.source(containing: fixture.protected.path) == nil)
        #expect(model.selectedEntryIDs == ids)
        #expect(model.inspectionConfiguration?.roots.map(\.id) == fixture.configuration.roots.map(\.id))
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
    @Test func cleanupMovesOnlyTheReviewedSubsetAndCanRestoreIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let other = fixture.cache.appendingPathComponent("another-old-cache")
        let contents = Data(repeating: 0x64, count: 32_768)
        try contents.write(to: other)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: other.path)
        let trash = fixture.directory.appendingPathComponent("fixture-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let engine = CacheEngine(configuration: fixture.configuration,
            activityDirectory: fixture.directory.appendingPathComponent("activity"), processProvider: { [] },
            fixtureTrashDirectory: trash, trashProvider: { original in
                let target = trash.appendingPathComponent(original.lastPathComponent)
                try FileManager.default.moveItem(at: original, to: target)
                return target
            })
        let model = RoomViewModel(engine: engine)
        model.scan()
        try await waitForScan(model)
        let source = try #require(model.sources.first)
        let exclude = try #require(model.cleanupCandidates(for: source.id).first { $0.path == other.path })
        model.toggleEntrySelection(id: exclude.id, sourceID: source.id)
        #expect(model.selectedEntryIDs.count == 1)
        await model.cleanSelected()
        try await waitForScan(model)
        #expect(model.selectedEntryIDs.isEmpty && model.selectedBytes == 0)
        #expect(model.selection.isEmpty)
        let record = try #require(model.activity.first)
        #expect(record.itemCount == 1)
        #expect(try Data(contentsOf: other) == contents)
        #expect(FileManager.default.fileExists(atPath: fixture.cache.appendingPathComponent("recent-cache").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.cache.appendingPathComponent("old-cache").path))
        await model.restore(record: record)
        try await waitForScan(model)
        #expect(model.selectedEntryIDs.isEmpty && model.selectedBytes == 0)
        #expect(model.selection.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.cache.appendingPathComponent("old-cache").path))
        #expect(try Data(contentsOf: other) == contents)
    }

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
