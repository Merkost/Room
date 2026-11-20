import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite @MainActor
struct RoomCachesCheckStoreTests {
    @Test func missingCheckHasNoCard() throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        #expect(RoomCachesCheckStore(defaults: fixture.defaults).check == nil)
    }

    @Test func completedScanStoresAllThreeValuesAndRelaunchReadsThem() async throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults)
        let model = RoomViewModel(engine: fixture.engine, cachesCheckStore: store)
        model.scan()
        try await fixture.waitForScan(model)
        let check = try #require(store.check)
        #expect(check.at == model.lastScanned)
        #expect(check.bytes == model.clearableBytes && check.bytes > 0)
        #expect(check.partial == model.hasPartialMeasurements)
        #expect(fixture.defaults.object(forKey: "RoomLastCachesCheckAt") as? Date == check.at)
        #expect((fixture.defaults.object(forKey: "RoomLastCachesCheckBytes") as? NSNumber)?.int64Value == check.bytes)
        #expect(fixture.defaults.object(forKey: "RoomLastCachesCheckPartial") as? Bool == check.partial)
        #expect(RoomCachesCheckStore(defaults: fixture.defaults).check == check)
    }

    @Test func runningAndStoppedScanLeavePreviousCheck() async throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults)
        let previous = RoomCachesCheck(at: Date(timeIntervalSince1970: 123), bytes: 8_400_000_000, partial: true)
        store.save(previous)
        let model = RoomViewModel(engine: fixture.engine, cachesCheckStore: store)
        model.scan()
        #expect(store.check == previous)
        model.cancelScan()
        try await fixture.waitForScan(model)
        #expect(model.lastScanned == nil)
        #expect(store.check == previous)
        #expect(RoomCachesCheckStore(defaults: fixture.defaults).check == previous)
    }

    @Test func invalidationSurvivesRelaunch() throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults)
        let at = Date(timeIntervalSince1970: 123)
        store.invalidate(at: at)
        #expect(RoomCachesCheckStore(defaults: fixture.defaults).invalidatedAt == at)
    }

    @Test func completedNewerScanSupersedesInvalidation() async throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults)
        let old = Date(timeIntervalSince1970: 123)
        store.invalidate(at: old)
        let model = RoomViewModel(engine: fixture.engine, cachesCheckStore: store)
        model.scan()
        try await fixture.waitForScan(model)
        let check = try #require(store.check)
        #expect(check.at > old)
        #expect(store.invalidatedAt == old)
    }

    @Test func stoppedScanDoesNotSupersede() async throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults)
        let at = Date(timeIntervalSince1970: 123)
        store.save(.init(at: at, bytes: 8_400_000_000, partial: false))
        store.invalidate(at: at.addingTimeInterval(1))
        let model = RoomViewModel(engine: fixture.engine, cachesCheckStore: store)
        model.scan()
        model.cancelScan()
        try await fixture.waitForScan(model)
        #expect(store.check?.at == at)
        #expect(store.invalidatedAt == at.addingTimeInterval(1))
    }

    #if ROOM_APP_STORE
    @Test func storeApprovalDoesNotInvalidate() async throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults)
        let model = RoomViewModel(engine: fixture.engine, cachesCheckStore: store)
        model.scan()
        try await fixture.waitForScan(model)
        try #require(model.canReviewCleanup)
        await model.prepareStoreCleanupReview()
        await model.cleanSelected() // No folder was approved by the user.
        #expect(model.errorMessage != nil)
        #expect(store.invalidatedAt == nil)
    }
    #else
    @Test func cleanAndRestoreInvalidateDirect() async throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults)
        let model = RoomViewModel(engine: fixture.engine, cachesCheckStore: store)
        model.scan()
        try await fixture.waitForScan(model)
        let check = try #require(store.check)

        await model.cleanSelected()
        #expect(!model.isScanning)
        model.cancelScan()
        try await fixture.waitForScan(model)
        let cleanup = try #require(store.invalidatedAt)
        #expect(cleanup > check.at)
        let record = try #require(model.activity.first)
        #expect(record.canRestore)
        #expect(record.details.filter(\.canRestore).count == 1)

        await model.restore(record: record)
        #expect(!model.isScanning)
        model.cancelScan()
        try await fixture.waitForScan(model)
        let restored = try #require(store.invalidatedAt)
        #expect(restored > cleanup)
        #expect(model.activity.first?.restoredCount == 1)
        #expect(RoomCachesCheckStore(defaults: fixture.defaults).invalidatedAt == restored)
    }

    @Test func failureKeepsInvalidation() async throws {
        let fixture = try CachesCheckFixture(moveFails: true)
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults)
        let model = RoomViewModel(engine: fixture.engine, cachesCheckStore: store)
        model.scan()
        try await fixture.waitForScan(model)
        let check = try #require(store.check)

        await model.cleanSelected()
        model.cancelScan()
        try await fixture.waitForScan(model)
        let invalidatedAt = try #require(store.invalidatedAt)
        #expect(invalidatedAt > check.at)
        #expect(model.activity.first?.bytes == 0)
        #expect(model.activity.first?.canRestore == false)
        #expect(RoomCachesCheckStore(defaults: fixture.defaults).invalidatedAt == invalidatedAt)
    }
    #endif

    @Test func incompleteDefaultsDoNotInventAZeroMeasurement() throws {
        let fixture = try CachesCheckFixture()
        defer { fixture.remove() }
        fixture.defaults.set(Date(), forKey: "RoomLastCachesCheckAt")
        #expect(RoomCachesCheckStore(defaults: fixture.defaults).check == nil)
    }
}

@MainActor private struct CachesCheckFixture {
    let suite = "RoomCachesCheckTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory: URL
    let engine: CacheEngine

    init(moveFails: Bool = false) throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = URL(fileURLWithPath: "/private/tmp/" + suite, isDirectory: true)   // the path the existing view model tests use; /var aliases are not scanned
        let cache = directory.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let old = cache.appendingPathComponent("old-cache")
        try Data(repeating: 0x51, count: 32_768).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: old.path)
        let configuration = CacheConfiguration(roots: [
            CacheRoot(id: "npm", title: "npm", subtitle: "Downloads", symbol: "shippingbox", category: "developer",
                      url: cache, consequence: "Rebuildable test cache.")
        ], homeDirectory: directory)
        let trash = directory.appendingPathComponent("fixture-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        engine = CacheEngine(configuration: configuration, activityDirectory: directory.appendingPathComponent("activity"),
            processProvider: { [] }, fixtureTrashDirectory: trash, trashProvider: { original in
                if moveFails { throw CocoaError(.fileWriteNoPermission) }
                let destination = trash.appendingPathComponent(original.lastPathComponent)
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            })
    }

    func waitForScan(_ model: RoomViewModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.isScanning && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isScanning)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
