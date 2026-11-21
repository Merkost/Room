import Foundation
import Testing
@testable import RoomApp

@MainActor
struct RoomSavedViewOpeningTests {
    @Test func missingApprovalCannotStartAMap() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "room-saved-views-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = RoomStateStore(directory: directory)
        let insights = RoomInsightsModel(access: RoomFileAccess(defaults: defaults), treeStore: RoomTreeStore(state: state),
            pressureStore: RoomPressureHistoryStore(directory: directory))
        let saved = RoomSavedView(id: UUID(), name: "Builds", root: .init(approvalID: "missing", relativePath: ""),
                                 nodePath: "", kind: .developer, mode: .map)
        #expect(await insights.openSavedDiskView(saved) == .needsAccess)
        #expect(!insights.isScanningDisk && insights.diskMap.current == nil)
    }

    @Test func approvedCacheMissMapsOnceAndReopeningUsesRetainedTree() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("Selected folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let name = "room-saved-views-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let fileAccess = RoomFileAccess(defaults: defaults)
        let approved = try fileAccess.remember(folder)
        let approval = try #require(fileAccess.folders.first)
        let state = RoomStateStore(directory: directory.appendingPathComponent("State", isDirectory: true))
        let trees = RoomTreeStore(state: state)
        let insights = RoomInsightsModel(access: fileAccess, treeStore: trees,
            pressureStore: RoomPressureHistoryStore(directory: directory))
        let saved = RoomSavedView(id: UUID(), name: "Builds", root: .init(approvalID: approval.id, relativePath: ""),
                                 nodePath: "", kind: .developer, mode: .map)
        #expect(await insights.openSavedDiskView(saved) == .opened)
        let retained = try #require(insights.diskMap.current)
        #expect(insights.diskMap.rootURL == approved)

        let missingNode = RoomSavedView(id: UUID(), name: "Former subfolder", root: saved.root,
                                       nodePath: "Archived", kind: nil, mode: .largest)
        #expect(await insights.openSavedDiskView(missingNode) == .rootOnly)
        #expect(insights.diskMap.current == retained && insights.diskMap.levelPath.isEmpty)
        await trees.flush()
    }
}
