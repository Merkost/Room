import Foundation
import RoomCore
import Testing
@testable import Room

@Suite("Disk Map retention")
struct RoomTreeStoreTests {
    private let root = RoomTreeLocation(approvalID: "approved-folder", relativePath: "Projects")
    private let day: TimeInterval = 86_400
    private let firstDate = Date(timeIntervalSince1970: 1_795_000_000)

    @Test func relaunchShowsLastMapAndNewestEligiblePrevious() async throws {
        let state = makeStorage()
        defer { try? FileManager.default.removeItem(at: state.directory) }
        let store = RoomTreeStore(state: state)

        await store.record(makeMap("root", date: firstDate), location: root, isHome: true)
        await store.record(makeMap("root", date: firstDate + day), location: root, isHome: true)
        await store.record(makeMap("root", date: firstDate + 5 * day), location: root, isHome: true)
        await store.flush()

        let reopened = RoomTreeStore(state: state)
        let restored = try #require(await reopened.lastOpened())
        #expect(restored.current.scannedAt == firstDate + 5 * day)
        #expect(restored.previous?.scannedAt == firstDate + day)
        #expect(restored.root.location.relativePath == "Projects")
        #expect(await reopened.home()?.rootID == "root")
    }

    @Test func stoppedMapDoesNotReplaceCompleteMap() async throws {
        let state = makeStorage()
        defer { try? FileManager.default.removeItem(at: state.directory) }
        let store = RoomTreeStore(state: state)
        await store.record(makeMap("root", date: firstDate), location: root, isHome: true)
        await store.record(makeMap("root", date: firstDate + day, cancelled: true), location: root, isHome: true)
        await store.flush()

        let reopened = RoomTreeStore(state: state)
        #expect(await reopened.current(rootID: "root")?.cancelled == false)
        #expect(await reopened.current(rootID: "root")?.scannedAt == firstDate)
    }

    @Test func changedDateAndForgetUseTheApprovedAncestor() async throws {
        let state = makeStorage()
        defer { try? FileManager.default.removeItem(at: state.directory) }
        let store = RoomTreeStore(state: state)
        let rootURL = URL(fileURLWithPath: "/private/example/owner", isDirectory: true)
        await store.setApprovals([root.approvalID: rootURL])
        await store.record(makeMap("root", date: firstDate), location: root, isHome: true)
        await store.markChanged(under: rootURL.appendingPathComponent("Projects2"), at: firstDate + day)
        #expect(await store.root(for: "root")?.changedAt == nil)
        await store.markChanged(under: rootURL.appendingPathComponent("Projects/fixture.txt"), at: firstDate + day)
        await store.flush()
        #expect(await store.root(for: "root")?.changedAt == firstDate + day)
        let storedNames = try FileManager.default.contentsOfDirectory(at: state.directory.appendingPathComponent("trees"),
            includingPropertiesForKeys: nil)
        for url in storedNames {
            #expect(try String(contentsOf: url, encoding: .utf8).contains(rootURL.path) == false)
        }
        await store.forget(approvalID: root.approvalID)
        await store.flush()
        #expect(await store.current(rootID: "root") == nil)
        #expect(await RoomTreeStore(state: state).home() == nil)
    }

    @MainActor @Test func retainedNavigationPreservesRootAndHandlesDepthCap() throws {
        let rootURL = URL(fileURLWithPath: "/root", isDirectory: true)
        let model = RoomDiskMapModel()
        var tree = leaf("", directory: true)
        var child = leaf("child", directory: true)
        child.children = [leaf("child/depth-capped", directory: true)]
        tree.children = [child]
        var map = makeMap("root", date: firstDate)
        map.tree = tree
        model.install(map, url: rootURL)
        #expect(model.go(to: "child"))
        #expect(model.level?.relativePath == "child")
        #expect(model.rootURL == rootURL)
        #expect(!model.go(to: "child/depth-capped"))
        model.stepOut()
        #expect(model.levelPath.isEmpty)
        #expect(model.current == map)
    }

    private func makeStorage() -> RoomStateStore {
        RoomStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func makeMap(_ id: String, date: Date, cancelled: Bool = false) -> RoomStoredTree {
        RoomStoredTree(rootID: id, displayPath: "~/Projects", scannedAt: date, cancelled: cancelled,
            volumeUUID: "volume", issueCount: 0, tree: leaf("", directory: true))
    }

    private func leaf(_ path: String, directory: Bool) -> RoomTreeNode {
        RoomTreeNode(name: path.split(separator: "/").last.map(String.init) ?? "Projects",
            relativePath: path, allocatedBytes: 4_096, fileCount: 1,
            kindBytes: ["documents": 4_096], isPartial: false, isDirectory: directory, children: [], other: nil)
    }
}
