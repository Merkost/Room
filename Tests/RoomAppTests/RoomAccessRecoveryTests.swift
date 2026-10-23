import Foundation
import Testing
@testable import RoomApp

@Suite("Saved folder recovery")
@MainActor
struct RoomAccessRecoveryTests {
    private let key = "RoomApprovedFolderBookmarks"

    @Test func legacyRecordsDecodeAndRetainUnavailableIdentity() throws {
        let name = "RoomAccessRecovery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let payload = [["id": "legacy-record", "bookmark": Data([1]).base64EncodedString()]]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: key)
        let store = RoomFileAccess(defaults: defaults, bookmarkResolver: { _ in throw CocoaError(.fileReadUnknown) })
        #expect(store.folders.isEmpty)
        #expect(store.unavailableFolders.count == 1)
        #expect(store.unavailableFolders.first?.id == "legacy-record")
        #expect(store.unavailableFolders.first?.path == nil)
        #expect(store.unavailableFolders.first?.reason == "Folder unavailable")
        #expect(store.scope(for: URL(fileURLWithPath: "/Users/example")) == nil)
        store.forget(id: "legacy-record")
        #expect(store.unavailableFolders.isEmpty)
    }

    @Test func staleAndUnavailableRecordsStayVisibleWithoutProvidingScope() throws {
        let name = "RoomAccessRecovery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try seed(defaults, [record("stale", byte: 1, path: "/Volumes/Work/Project"),
                            record("missing", byte: 2, path: "/Volumes/Offline/Archive"),
                            record("valid", byte: 3, path: "/Users/example/Approved")])
        let store = RoomFileAccess(defaults: defaults, bookmarkResolver: { data in
            switch data.first {
            case 1: RoomBookmarkResolution(url: URL(fileURLWithPath: "/Volumes/Work/Project"), isStale: true)
            case 3: RoomBookmarkResolution(url: URL(fileURLWithPath: "/Users/example/Approved"), isStale: false)
            default: throw CocoaError(.fileReadNoSuchFile)
            }
        })
        #expect(store.folders.map(\.id) == ["valid"])
        #expect(Set(store.unavailableFolders.map(\.id)) == ["stale", "missing"])
        #expect(store.unavailableFolders.first { $0.id == "stale" }?.reason == "Approval needs renewal")
        #expect(store.unavailableFolders.first { $0.id == "missing" }?.path == "/Volumes/Offline/Archive")
        #expect(store.scope(for: URL(fileURLWithPath: "/Volumes/Work/Project/.cache")) == nil)
        #expect(store.scope(for: URL(fileURLWithPath: "/Volumes/Offline/Archive")) == nil)
        #expect(store.scope(for: URL(fileURLWithPath: "/Users/example/Approved/.cache")) != nil)
    }

    @Test func explicitRenewalReplacesOnlyTheChosenRecordAndKeepsItsID() throws {
        let name = "RoomAccessRecovery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try seed(defaults, [record("renew-me", byte: 1, path: "/Volumes/Old/Project"),
                            record("keep-me", byte: 2, path: "/Volumes/Other/Archive")])
        let approved = URL(fileURLWithPath: "/Volumes/Work/Approved", isDirectory: true)
        let store = RoomFileAccess(defaults: defaults, bookmarkResolver: { data in
            guard data == Data([9]) else { throw CocoaError(.fileReadNoSuchFile) }
            return RoomBookmarkResolution(url: approved, isStale: false)
        }, bookmarkCreator: { url in
            #expect(url == approved)
            return Data([9])
        })
        let result = try store.renew(id: "renew-me", approvedURL: approved)
        #expect(result == approved)
        #expect(store.folders.map(\.id) == ["renew-me"])
        #expect(store.unavailableFolders.map(\.id) == ["keep-me"])
        #expect(store.unavailableFolders.first?.path == "/Volumes/Other/Archive")
        let saved = try records(defaults)
        #expect(saved.count == 2)
        #expect(saved.first { $0["id"] as? String == "renew-me" }?["lastKnownPath"] as? String == approved.path)
        #expect(saved.first { $0["id"] as? String == "keep-me" }?["bookmark"] as? String == Data([2]).base64EncodedString())
        #expect(store.scope(for: approved.appendingPathComponent(".hidden")) == approved)
        #expect(store.scope(for: URL(fileURLWithPath: "/Volumes/Old/Project")) == nil)
    }

    @Test func failedRenewalDoesNotReplaceTheSavedRecord() throws {
        let name = "RoomAccessRecovery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try seed(defaults, [record("keep-identity", byte: 1, path: "/Volumes/Original/Project")])
        let before = try #require(defaults.data(forKey: key))
        let store = RoomFileAccess(defaults: defaults, bookmarkResolver: { _ in throw CocoaError(.fileReadUnknown) },
                                   bookmarkCreator: { _ in Data([9]) })
        #expect(throws: (any Error).self) {
            try store.renew(id: "keep-identity", approvedURL: URL(fileURLWithPath: "/Volumes/Chosen"))
        }
        #expect(defaults.data(forKey: key) == before)
        #expect(store.folders.isEmpty)
        #expect(store.unavailableFolders.first?.id == "keep-identity")
        #expect(store.unavailableFolders.first?.path == "/Volumes/Original/Project")
    }

    @Test func renewalCannotResurrectAnEntryForgottenByAnotherStore() throws {
        let name = "RoomAccessRecovery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try seed(defaults, [record("forgotten", byte: 1, path: "/Volumes/Original/Project")])
        let a = RoomFileAccess(defaults: defaults, bookmarkResolver: { _ in throw CocoaError(.fileReadUnknown) })
        var creations = 0
        let b = RoomFileAccess(defaults: defaults, bookmarkResolver: { _ in throw CocoaError(.fileReadUnknown) }, bookmarkCreator: { _ in
            creations += 1
            return Data([9])
        })
        a.forget(id: "forgotten")
        #expect(throws: (any Error).self) {
            try b.renew(id: "forgotten", approvedURL: URL(fileURLWithPath: "/Volumes/Chosen"))
        }
        #expect(creations == 0)
        #expect(try records(defaults).isEmpty)
        #expect(b.unavailableFolders.isEmpty)
    }

    private func record(_ id: String, byte: UInt8, path: String) -> [String: Any] {
        ["id": id, "bookmark": Data([byte]).base64EncodedString(), "lastKnownPath": path,
         "lastKnownName": URL(fileURLWithPath: path).lastPathComponent]
    }

    private func seed(_ defaults: UserDefaults, _ payload: [[String: Any]]) throws {
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: key)
    }

    private func records(_ defaults: UserDefaults) throws -> [[String: Any]] {
        let data = try #require(defaults.data(forKey: key))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [[String: Any]])
    }
}
