import Foundation
import Testing
@testable import RoomApp

@Suite("Approved folder boundaries")
@MainActor
struct RoomFileAccessTests {
    @Test func grantIncludesOnlyTheChosenFolderAndDescendants() {
        let root = URL(fileURLWithPath: "/Users/example/Documents/Project", isDirectory: true)
        #expect(RoomFileAccess.contains(parent: root, child: root))
        #expect(RoomFileAccess.contains(parent: root, child: root.appendingPathComponent(".hidden/cache")))
        #expect(!RoomFileAccess.contains(parent: root, child: URL(fileURLWithPath: "/Users/example/Documents/Project-other")))
        #expect(!RoomFileAccess.contains(parent: root, child: URL(fileURLWithPath: "/Users/example/Documents/Project/../Private")))
        #expect(!RoomFileAccess.contains(parent: root, child: URL(string: "https://example.com")!))
    }

    @Test func freshStoreDoesNotInventAccess() throws {
        let name = "RoomAccessTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RoomFileAccess(defaults: defaults)
        #expect(store.folders.isEmpty)
        #expect(store.scope(for: FileManager.default.homeDirectoryForCurrentUser) == nil)
    }

    @Test func invalidSavedBookmarksDoNotGrantAccess() throws {
        let name = "RoomAccessTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let payload = [["id": "invalid", "bookmark": Data([1, 2, 3]).base64EncodedString()]]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: "RoomApprovedFolderBookmarks")
        let store = RoomFileAccess(defaults: defaults)
        #expect(store.folders.isEmpty)
        #expect(store.note != nil)
    }

    @Test func approvedBookmarkRoundTripUsesItsResolvedURLAndCanBeForgotten() throws {
        let name = "RoomAccessTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: fixture)
        }
        let store = RoomFileAccess(defaults: defaults)
        let approved = try store.remember(fixture)
        #expect(approved.resolvingSymlinksInPath().path == fixture.resolvingSymlinksInPath().path)
        #expect(store.scope(for: approved) != nil)
        let reloaded = RoomFileAccess(defaults: defaults)
        #expect(reloaded.folders.count == 1)
        #expect(reloaded.scope(for: approved.appendingPathComponent("child")) != nil)
        reloaded.forget(id: try #require(reloaded.folders.first?.id))
        #expect(RoomFileAccess(defaults: defaults).folders.isEmpty)
    }

    @Test func staleStoresMergeAdditionsAndCannotResurrectRemovedGrants() throws {
        let name = "RoomAccessMergeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let a = RoomFileAccess(defaults: defaults)
        let b = RoomFileAccess(defaults: defaults)
        _ = try a.remember(first)
        _ = try b.remember(second)
        let combined = RoomFileAccess(defaults: defaults)
        #expect(combined.folders.count == 2)
        let firstID = try #require(combined.folders.first { $0.name == "first" }?.id)
        b.forget(id: firstID)
        _ = try a.remember(second)
        let final = RoomFileAccess(defaults: defaults)
        #expect(final.folders.count == 1)
        #expect(final.folders.first?.name == "second")
    }
}
