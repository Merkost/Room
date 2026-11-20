#if ROOM_APP_STORE
import Foundation
import RoomCore
import Testing
@testable import RoomApp

@Suite("Store read-grant scan invalidation") @MainActor
struct RoomStoreGrantRevocationTests {
    @Test("Revocation clears partial rows and fences a complete scan before it can publish")
    func forgottenGrantFencesFinishedScan() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/Room-StoreRevocation-" + UUID().uuidString, isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = cache.appendingPathComponent("old-download")
        let contents = Data(repeating: 0x72, count: 8_192)
        try contents.write(to: item)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: item.path)
        let defaults = try #require(UserDefaults(suiteName: root.lastPathComponent))
        defer { defaults.removePersistentDomain(forName: root.lastPathComponent) }
        let access = RoomFileAccess(defaults: defaults)
        _ = try access.remember(cache)
        let id = try #require(access.folders.first?.id)
        let configuration = CacheConfiguration(roots: [
            CacheRoot(id: "owned-cache", title: "Owned cache", subtitle: "Fixture", symbol: "shippingbox",
                category: "developer", url: cache, consequence: "Rebuildable downloads", minimumAge: 0),
        ], homeDirectory: root)
        let engine = CacheEngine(configuration: configuration, activityDirectory: root.appendingPathComponent("activity"))
        let checks = RoomCachesCheckStore(defaults: defaults)
        let handoff = StoreScanHandoff()
        defer { handoff.release() }
        let model = RoomViewModel(engine: engine, cachesCheckStore: checks, access: access,
                                  beforeScanPublication: { await handoff.pauseOnce($0) })
        model.scan()
        let obsolete = try #require(model.scanTask)
        var reports = handoff.ready.stream.makeAsyncIterator()
        let completed = try #require(await reports.next())
        #expect(!completed.cancelled && completed.eligibleBytes > 0)

        access.forget(id: id)
        model.storeAccessChanged()
        #expect(!model.isScanning && model.scanTask == nil && model.sources.isEmpty)
        #expect(model.selection.isEmpty && model.lastScanned == nil && !model.canReviewCleanup)
        handoff.release()
        await obsolete.value
        #expect(model.sources.isEmpty && model.protectedSources.isEmpty)
        #expect(model.lastScanned == nil && !model.canReviewCleanup && !model.canRunStoreCleanup)
        #expect(model.selectedBytes == 0 && checks.check == nil)
        #expect(model.storeReviewLocations.isEmpty && model.storeGrantedPaths.isEmpty)

        _ = try access.remember(cache)
        model.scan()
        let fresh = try #require(model.scanTask)
        await fresh.value
        #expect(model.hasReport && model.canReviewCleanup && model.clearableBytes > 0)
        #expect(!model.canRunStoreCleanup && model.storeGrantedPaths.isEmpty)
        #expect(try Data(contentsOf: item) == contents)
        #expect(await engine.history().isEmpty)
    }
}

@MainActor
private final class StoreScanHandoff {
    let ready = AsyncStream<ScanReport>.makeStream()
    private var releaseScan: CheckedContinuation<Void, Never>?
    private var didPause = false

    func pauseOnce(_ report: ScanReport) async {
        guard !didPause else { return }
        didPause = true
        await withCheckedContinuation { continuation in
            releaseScan = continuation
            ready.continuation.yield(report)
            ready.continuation.finish()
        }
    }

    func release() {
        releaseScan?.resume()
        releaseScan = nil
    }
}
#endif
