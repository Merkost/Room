import Foundation
import Testing
@testable import RoomApp

@Suite @MainActor
struct RoomStateMigrationTests {
    @Test func cachesDefaultsCopiedOnce() async throws {
        let fixture = try CacheMigrationFixture()
        defer { fixture.remove() }
        let first = RoomCachesCheckStore(defaults: fixture.defaults, writer: fixture.writer)
        await first.waitForLoad()
        #expect(first.check == fixture.legacyCheck)
        #expect(first.invalidatedAt == fixture.invalidation)
        let saved = try Data(contentsOf: fixture.reportsURL)
        #expect(RoomStateCodec.classify(saved, currentSchema: 1) == .current)
        fixture.defaults.set(42, forKey: RoomLegacyCachesCheck.keys.bytes)
        let next = RoomCachesCheckStore(defaults: fixture.defaults, writer: fixture.writer)
        await next.waitForLoad()
        #expect(next.check == fixture.legacyCheck)
        #expect(try Data(contentsOf: fixture.reportsURL) == saved)
    }

    @Test func partialDefaultsNotMigrated() async throws {
        let fixture = try CacheMigrationFixture()
        defer { fixture.remove() }
        fixture.defaults.removeObject(forKey: RoomLegacyCachesCheck.keys.partial)
        let cache = RoomCachesCheckStore(defaults: fixture.defaults, writer: fixture.writer)
        await cache.waitForLoad()
        #expect(cache.check == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.reportsURL.path))
    }

    @Test func defaultsLeftForDowngrade() async throws {
        let fixture = try CacheMigrationFixture()
        defer { fixture.remove() }
        let store = RoomCachesCheckStore(defaults: fixture.defaults, writer: fixture.writer)
        await store.waitForLoad()
        let newer = RoomCachesCheck(at: fixture.legacyCheck.at.addingTimeInterval(1), bytes: 100, partial: false)
        store.save(newer)
        await fixture.writer.flush(deadline: .seconds(5))
        let model = RoomCachesCheckStore(defaults: fixture.defaults, writer: fixture.writer)
        await model.waitForLoad()
        #expect(model.check == newer)
        #expect(fixture.defaults.object(forKey: RoomLegacyCachesCheck.keys.at) as? Date == fixture.legacyCheck.at)
        #expect(fixture.defaults.object(forKey: RoomLegacyCachesCheck.keys.bytes) as? Int64 == fixture.legacyCheck.bytes)
        #expect(fixture.defaults.object(forKey: RoomLegacyCachesCheck.keys.partial) as? Bool == fixture.legacyCheck.partial)
    }

    @Test func activityReceiptsUntouched() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let activity = directory.appendingPathComponent("Activity", isDirectory: true)
        try FileManager.default.createDirectory(at: activity, withIntermediateDirectories: false)
        let receipt = activity.appendingPathComponent("receipt.json")
        let contents = Data("{\"receipt\":true}".utf8)
        try contents.write(to: receipt)
        let state = RootState(directory: directory)
        try await state.actor.write(["map"], to: .tree(rootID: "abc"), generation: 1)
        try await state.actor.write(["check"], to: .reports, generation: 1)
        try await state.actor.write(["ledger"], to: .ledger, generation: 1)
        let forgotten = await state.actor.forgetHistory()
        #expect(Set(forgotten) == ["reports.json", "trees/abc.json"])
        #expect(try Data(contentsOf: receipt) == contents)
        #expect(await state.actor.load([String].self, from: .ledger).value == ["ledger"])
    }
}

private struct RootState {
    let actor: RoomStateStore
    init(directory: URL) { actor = RoomStateStore(directory: directory.appendingPathComponent("State")) }
}

@MainActor private struct CacheMigrationFixture {
    let directory: URL
    let suite = "RoomStateMigration-\(UUID())"
    let defaults: UserDefaults
    let writer: RoomStateWriter
    let legacyCheck = RoomCachesCheck(at: Date(timeIntervalSince1970: 1_600_000_000), bytes: 8_000_000_000, partial: true)
    let invalidation = Date(timeIntervalSince1970: 1_620_000_000)
    var reportsURL: URL { directory.appendingPathComponent(RoomStateFile.reports.name) }

    init() throws {
        directory = try reserveStateFixture()
        defaults = try #require(UserDefaults(suiteName: suite))
        writer = RoomStateWriter(store: RoomStateStore(directory: directory))
        let keys = RoomLegacyCachesCheck.keys
        defaults.set(legacyCheck.at, forKey: keys.at)
        defaults.set(legacyCheck.bytes, forKey: keys.bytes)
        defaults.set(legacyCheck.partial, forKey: keys.partial)
        defaults.set(invalidation, forKey: keys.invalidatedAt)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
