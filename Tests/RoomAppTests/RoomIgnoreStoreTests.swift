import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@MainActor struct RoomIgnoreStoreTests {
    @Test func ruleMatchesDirectoryBoundaries() {
        let rule = RoomIgnoreRule(id: UUID(), path: "/tmp/cache", accessFolderID: nil, addedAt: Date())
        #expect(RoomIgnoreFilter.isIgnored(rootPath: "/tmp/cache", rules: [rule]))
        #expect(RoomIgnoreFilter.isIgnored(rootPath: "/tmp/cache/downloads", rules: [rule]))
        #expect(!RoomIgnoreFilter.isIgnored(rootPath: "/tmp/caches", rules: [rule]))
    }

    #if !ROOM_APP_STORE
    @Test func familyKeepsNonIgnoredGroupsAndUndoRestoresSelectedBytes() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("RoomIgnore-\(UUID())", isDirectory: true)
        let ignored = root.appendingPathComponent("npm-old", isDirectory: true)
        let kept = root.appendingPathComponent("npm-new", isDirectory: true)
        let folders = [ignored, kept]
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4096).write(to: folder.appendingPathComponent("item"))
        }
        let state = RoomStateStore(directory: root.appendingPathComponent("State"))
        let store = RoomIgnoreStore(state: state)
        _ = try await store.add([(ignored, nil)])
        let roots = folders.map { CacheRoot(id: $0.lastPathComponent, title: "Fixture", subtitle: "",
            symbol: "archivebox", category: "developer", url: $0, consequence: "Re-download", minimumAge: 0) }
        let engine = CacheEngine(configuration: .init(roots: roots, homeDirectory: root),
            activityDirectory: root.appendingPathComponent("activity"), processProvider: { [] })
        let suite = root.lastPathComponent
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let check = RoomCachesCheckStore(defaults: defaults)
        let model = RoomViewModel(engine: engine, cachesCheckStore: check, ignoreStore: store)
        model.scan()
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        let family = try #require(model.sources.first)
        #expect(family.id == "npm" && family.bytes == 8192)
        #expect(family.eligibleBytes == 4096 && check.check?.bytes == 4096)
        #expect(family.heldReasons.first?.reason == "You asked Room not to suggest this")

        let added = await model.neverSuggest(family)
        #expect(added.count == 1 && model.clearableBytes == 0 && check.check?.bytes == 0)
        await model.removeIgnoreRules(added)
        #expect(model.clearableBytes == 4096 && check.check?.bytes == 4096)
        #expect(store.rules.map(\.path) == [ignored.path])
        let raw = await engine.scan()
        #expect(raw.eligibleBytes == 8192)
    }
    #endif
}
