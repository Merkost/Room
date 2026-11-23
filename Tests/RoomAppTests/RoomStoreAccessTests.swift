#if ROOM_APP_STORE
import Foundation
import Synchronization
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Store native review boundaries") @MainActor
struct RoomStoreAccessTests {
    @Test func replacingAnEqualSizeItemNeedsFreshApprovalWhileNarrowingKeepsIt() async throws {
        let fixture = try StoreAccessFixture()
        defer { fixture.remove() }
        for name in ["first", "second"] {
            try Data(repeating: 0x71, count: 4096).write(to: fixture.cache.appendingPathComponent(name))
        }
        let configuration = CacheConfiguration(roots: [
            CacheRoot(id: "fixture", title: "Fixture", subtitle: "Owned fixture", symbol: "shippingbox",
                category: "developer", url: fixture.cache, consequence: "Rebuildable", minimumAge: 0),
        ], homeDirectory: fixture.root)
        let engine = CacheEngine(configuration: configuration, activityDirectory: fixture.root.appendingPathComponent("activity"))
        let defaults = try #require(UserDefaults(suiteName: fixture.root.lastPathComponent))
        defer { defaults.removePersistentDomain(forName: fixture.root.lastPathComponent) }
        let picker = StorePickerState()
        let model = RoomViewModel(engine: engine, cachesCheckStore: RoomCachesCheckStore(defaults: defaults),
            access: RoomFileAccess(defaults: defaults), storePicker: { _, _ in picker.selected })
        model.scan()
        await model.scanTask?.value
        let source = try #require(model.sources.first)
        let items = model.cleanupCandidates(for: source.id)
        try #require(items.count == 2 && items[0].bytes == items[1].bytes)
        let folder = try #require(items.first?.url.deletingLastPathComponent())
        await model.prepareStoreCleanupReview()
        picker.selected = fixture.root
        await model.allowStoreReviewLocation(folder)
        #expect(model.errorMessage != nil && model.storeGrantedPaths.isEmpty)
        picker.selected = fixture.cache
        await model.allowStoreReviewLocation(folder)
        #expect(model.errorMessage == nil && model.canRunStoreCleanup)

        model.toggleEntrySelection(id: items[1].id, sourceID: source.id)
        #expect(model.storeGrantedPaths == [folder.path] && model.canRunStoreCleanup)
        let priorBytes = model.selectedBytes
        model.toggleEntrySelection(id: items[1].id, sourceID: source.id)
        model.toggleEntrySelection(id: items[0].id, sourceID: source.id)
        #expect(model.selectedBytes == priorBytes)
        #expect(model.selectedEntryIDs == [items[1].id])
        #expect(model.storeGrantedPaths.isEmpty && !model.canRunStoreCleanup)
        await model.allowStoreReviewLocation(folder)
        #expect(model.canRunStoreCleanup)
    }

    @Test func narrowKeepsRemainingGrantsAndEndsDroppedScopes() async throws {
        let fixture = try StoreAccessFixture()
        defer { fixture.remove() }
        let state = StorePickerState()
        let review = RoomStoreFolderReview(picker: { _, _ in state.selected },
            beginScope: { _ in state.starts += 1; return true }, endScope: { _ in state.ends += 1 })
        try review.prepare([fixture.cache, fixture.trash])
        state.selected = fixture.cache
        try await review.allow(fixture.cache)
        state.selected = fixture.trash
        try await review.allow(fixture.trash)
        review.narrow(to: [fixture.cache.path])
        #expect(review.grantedPaths == [fixture.cache.path] && state.ends == 1)
        try review.validate(exactly: [fixture.cache])
        #expect(throws: (any Error).self) { try review.validate(exactly: [fixture.cache, fixture.trash]) }

        try review.add([fixture.cache, fixture.trash])
        #expect(review.grantedPaths == [fixture.cache.path] && !review.allGranted)
        #expect(throws: (any Error).self) { try review.validate(exactly: [fixture.cache, fixture.trash]) }
        try await review.allow(fixture.trash)
        try review.validate(exactly: [fixture.cache, fixture.trash])
        review.discard()
        #expect(state.starts == state.ends)
    }

    @Test func exactPhysicalApprovalRejectsParentsLinksAndReplacements() async throws {
        let fixture = try StoreAccessFixture()
        defer { fixture.remove() }
        let state = StorePickerState()
        let review = RoomStoreFolderReview(picker: { _, _ in state.selected },
            beginScope: { _ in state.starts += 1; return true }, endScope: { _ in state.ends += 1 })
        try review.prepare([fixture.cache])
        #expect(!review.allGranted)
        state.selected = fixture.root
        await #expect(throws: (any Error).self) { try await review.allow(fixture.cache) }
        #expect(!review.allGranted && state.starts == state.ends)
        let link = fixture.root.appendingPathComponent("linked-cache")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.cache)
        state.selected = link
        await #expect(throws: (any Error).self) { try await review.allow(fixture.cache) }
        #expect(!review.allGranted && state.starts == state.ends)
        state.selected = fixture.cache
        try await review.allow(fixture.cache)
        try review.validate(exactly: [fixture.cache])
        #expect(review.allGranted)
        try FileManager.default.moveItem(at: fixture.cache, to: fixture.root.appendingPathComponent("old-cache"))
        try FileManager.default.createDirectory(at: fixture.cache, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try review.validate(exactly: [fixture.cache]) }
        review.discard()
        #expect(!review.allGranted && review.locations.isEmpty && state.starts == state.ends)
    }

    @Test func dismissedReviewCannotReceiveAnInFlightPickerGrant() async throws {
        let fixture = try StoreAccessFixture()
        defer { fixture.remove() }
        let state = StorePickerState()
        let review = RoomStoreFolderReview(picker: { _, _ in
            await withCheckedContinuation { state.continuation = $0 }
        }, beginScope: { _ in state.starts += 1; return true }, endScope: { _ in state.ends += 1 })
        try review.prepare([fixture.cache])
        let request = Task { try await review.allow(fixture.cache) }
        for _ in 0..<20 where state.continuation == nil { await Task.yield() }
        let continuation = try #require(state.continuation)
        review.discard()
        continuation.resume(returning: fixture.cache)
        try await request.value
        #expect(review.grantedPaths.isEmpty && state.starts == 0)
    }

    @Test func eligibleScanCannotMoveWithoutExactReviewedWriteGrants() async throws {
        let fixture = try StoreAccessFixture()
        defer { fixture.remove() }
        let data = Data(repeating: 0x71, count: 4096)
        let item = fixture.cache.appendingPathComponent("old-download")
        try data.write(to: item)
        let calls = Mutex(0)
        let configuration = CacheConfiguration(roots: [CacheRoot(id: "fixture-cache", title: "Fixture cache", subtitle: "Owned fixture",
            symbol: "shippingbox", category: "developer", url: fixture.cache, consequence: "Can rebuild", minimumAge: 0)], homeDirectory: fixture.root)
        let engine = CacheEngine(configuration: configuration, activityDirectory: fixture.root.appendingPathComponent("activity"),
            processProvider: { [] }, fixtureTrashDirectory: fixture.trash, trashProvider: { source in
                calls.withLock { $0 += 1 }
                let destination = fixture.trash.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.moveItem(at: source, to: destination)
                return destination
            })
        let defaults = try #require(UserDefaults(suiteName: fixture.root.lastPathComponent))
        defer { defaults.removePersistentDomain(forName: fixture.root.lastPathComponent) }
        let model = RoomViewModel(engine: engine, cachesCheckStore: RoomCachesCheckStore(defaults: defaults))
        model.scan()
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isScanning)
        #expect(model.scanIssues.isEmpty, "Fixture scan issues: \(model.scanIssues.joined(separator: "; "))")
        let source = try #require(model.sources.first)
        #expect(source.blockedReason == nil, "Unexpected fixture hold: \(source.blockedReason ?? "none")")
        #expect(source.eligibleBytes == Int64(data.count))
        #expect(source.cleanupConsequences == ["Can rebuild"])
        #expect(model.selection == [source.id])
        #expect(model.selectedBytes == Int64(data.count) && model.canReviewCleanup)
        await model.cleanSelected()
        #expect(calls.withLock { $0 } == 0)
        #expect(try Data(contentsOf: item) == data)
        #expect(!model.canRunStoreCleanup)
        await model.prepareStoreCleanupReview()
        #expect(!model.storeReviewLocations.isEmpty && !model.storeAllLocationsGranted)
        await model.cleanSelected()
        #expect(calls.withLock { $0 } == 0)
        #expect(try Data(contentsOf: item) == data)
        model.discardStoreReview()
    }
}

@MainActor private final class StorePickerState {
    var selected: URL?
    var starts = 0
    var ends = 0
    var continuation: CheckedContinuation<URL?, Never>?
}

private struct StoreAccessFixture {
    let root: URL
    let cache: URL
    let trash: URL
    init() throws {
        // Keep the physical spelling: Foundation can rewrite resolved /private/var
        // paths to /var aliases, which the scanner correctly refuses to traverse.
        root = URL(fileURLWithPath: "/private/tmp/Room-StoreAccess-" + UUID().uuidString, isDirectory: true)
        cache = root.appendingPathComponent("cache", isDirectory: true)
        trash = root.appendingPathComponent("fixture-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
#endif
