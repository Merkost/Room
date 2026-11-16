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

    init() throws {
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
        engine = CacheEngine(configuration: configuration, activityDirectory: directory.appendingPathComponent("activity"))
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
