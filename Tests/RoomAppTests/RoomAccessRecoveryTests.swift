import Foundation
import Testing
@testable import RoomApp

@Suite("Read access recovery") @MainActor
struct RoomAccessRecoveryTests {
    @Test func staleApprovalRenewsOnlyItsOriginalFolderAndKeepsItsIdentity() throws {
        let suite = "RoomAccessRecovery-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stale = Data("stale".utf8)
        let original = URL(filePath: "/private/tmp/Room Original")
        let different = URL(filePath: "/private/tmp/Room Different")
        let record = [["id": "original-approval", "bookmark": stale.base64EncodedString()]]
        defaults.set(try JSONEncoder().encode(record), forKey: "RoomApprovedFolderBookmarks")
        let access = RoomFileAccess(defaults: defaults, bookmarkResolver: { data in
            if data == stale { return RoomBookmarkResolution(url: original, isStale: true) }
            let path = try #require(String(data: data, encoding: .utf8))
            return RoomBookmarkResolution(url: URL(filePath: path), isStale: false)
        }, bookmarkCreator: { Data($0.path.utf8) })

        let unavailable = try #require(access.unavailableFolders.first)
        #expect(access.scope(for: original) == nil)
        #expect(unavailable.url == original)
        #expect(throws: CocoaError.self) { try access.renew(id: unavailable.id, approvedURL: different) }
        #expect(access.folders.isEmpty)
        access.stageRemoval(id: unavailable.id)
        #expect(throws: CocoaError.self) { try access.renew(id: unavailable.id, approvedURL: original) }
        access.undoRemoval(id: unavailable.id)
        try access.renew(id: unavailable.id, approvedURL: original)
        #expect(access.unavailableFolders.isEmpty)
        #expect(access.folders.first?.id == "original-approval")
        #expect(access.scope(for: original) == original)
    }
}
