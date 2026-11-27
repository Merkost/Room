import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

#if !ROOM_APP_STORE
@MainActor struct RoomCachesRecentTests {
    @Test func recentCachesAreListedUntickedAndMoveOnlyWhenTicked() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model(running: [])
        await fixture.check(model)

        let row = try #require(model.recentRows.first)
        #expect(model.recentRows.count == 1 && model.inUseRows.isEmpty)
        #expect(row.note == "used today" && row.bytes > 0)
        #expect(model.clearableBytes > 0 && model.foundBytes == model.clearableBytes + row.bytes)
        #expect(!model.selection.contains(row.id), "recent is never ticked for you")
        model.selectRecommended()
        #expect(!model.selection.contains(row.id) && model.selectedBytes == model.clearableBytes)

        model.toggleSelection(id: row.id)
        #expect(model.selectedBytes == model.foundBytes)
        #expect(model.cleanupRows.contains { $0.id == row.id && !$0.entryIDs.isEmpty })
        await model.cleanSelected()
        #expect(!FileManager.default.fileExists(atPath: fixture.fresh.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.old.path))
        #expect(model.recentRows.isEmpty && model.foundBytes == 0)
    }

    @Test func recentCachesStayWhenNotTicked() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model(running: [])
        await fixture.check(model)
        await model.cleanSelected()
        #expect(FileManager.default.fileExists(atPath: fixture.fresh.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.old.path))
    }

    @Test func aRunningAppIsListedButCannotBeTicked() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model(running: ["owner"])
        await fixture.check(model)
        #expect(model.recentRows.isEmpty && model.clearableBytes == 0)
        let row = try #require(model.inUseRows.first)
        #expect(row.note == "Owner is running")
        model.toggleSelection(id: row.id)
        #expect(model.selection.isEmpty && model.foundBytes == row.bytes)
    }

    @MainActor private struct Fixture {
        let base: URL
        let old: URL
        let fresh: URL

        init() throws {
            base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("RoomRecentApp-\(UUID())", isDirectory: true)
            old = base.appendingPathComponent("cache/old")
            fresh = base.appendingPathComponent("cache/fresh")
            for folder in ["cache", "trash"] {
                try FileManager.default.createDirectory(at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            for file in [old, fresh] { try Data(repeating: 1, count: 4096).write(to: file) }
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)],
                                                  ofItemAtPath: old.path)
        }

        func model(running: [String]) -> RoomViewModel {
            let trash = base.appendingPathComponent("trash", isDirectory: true)
            let root = CacheRoot(id: "fixture", title: "Fixture", subtitle: "", symbol: "archivebox", category: "developer",
                url: base.appendingPathComponent("cache", isDirectory: true), consequence: "Rebuilt", guardedProcesses: ["owner"])
            let engine = CacheEngine(configuration: .init(roots: [root], homeDirectory: base),
                activityDirectory: base.appendingPathComponent("activity"), processProvider: { running },
                fixtureTrashDirectory: trash, trashProvider: { original in
                    let destination = trash.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.moveItem(at: original, to: destination)
                    return destination
                })
            let defaults = UserDefaults(suiteName: base.lastPathComponent)!
            return RoomViewModel(engine: engine, cachesCheckStore: RoomCachesCheckStore(defaults: defaults))
        }

        func check(_ model: RoomViewModel) async {
            model.scan()
            for _ in 0..<300 where model.isScanning { try? await Task.sleep(for: .milliseconds(10)) }
        }

        func remove() {
            UserDefaults(suiteName: base.lastPathComponent)?.removePersistentDomain(forName: base.lastPathComponent)
            try? FileManager.default.removeItem(at: base)
        }
    }
}
#endif
