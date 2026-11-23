import Foundation
import Testing
@testable import RoomApp

@MainActor
struct RoomSavedViewsStoreTests {
    let root = RoomTreeLocation(approvalID: "approved-folder", relativePath: "Projects/App")

    @Test func savesFullPresetAndRestoresAfterRelaunch() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        let writer = RoomStateWriter(store: state)
        let store = RoomSavedViewsStore(writer: writer)
        #expect(!store.canAdd)
        await store.load()
        let preset = try #require(store.add(name: "  Largest archives  ", root: root,
            nodePath: "Builds", kind: .archives, mode: .largest))
        #expect(preset.name == "Largest archives")
        #expect(store.rename(preset.id, to: "Build archives"))
        await writer.flush(deadline: .seconds(2))

        let reopened = RoomSavedViewsStore(writer: RoomStateWriter(store: RoomStateStore(directory: directory)))
        await reopened.load()
        let saved = try #require(reopened.visible.first)
        #expect(saved.id == preset.id && saved.name == "Build archives")
        #expect(saved.root == root && saved.nodePath == "Builds" && saved.mode == .largest && saved.kind == .archives)
    }

    @Test func rejectsUnsafeLocationsAndCapsViewCount() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        let store = RoomSavedViewsStore(writer: RoomStateWriter(store: state))
        await store.load()
        #expect(store.add(name: "Out of scope", root: root, nodePath: "../Something", kind: nil, mode: .map) == nil)
        #expect(store.add(name: "Absolute path", root: .init(approvalID: root.approvalID, relativePath: "/tmp"),
            nodePath: "", kind: nil, mode: .map) == nil)
        #expect(store.add(name: "  ", root: root, nodePath: "", kind: nil, mode: .map) == nil)
        for number in 1...RoomSavedView.limit {
            #expect(store.add(name: "Preset \(number)", root: root, nodePath: "", kind: nil, mode: .map) != nil)
        }
        #expect(!store.canAdd)
        #expect(store.add(name: "One too many", root: root, nodePath: "", kind: nil, mode: .map) == nil)
    }

    @Test func undoRestoresTheRecordAndCommitRemovesIt() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        let writer = RoomStateWriter(store: state)
        let store = RoomSavedViewsStore(writer: writer)
        await store.load()
        let preset = try #require(store.add(name: "Builds", root: root, nodePath: "", kind: .developer, mode: .map))
        store.stageRemoval(preset.id)
        #expect(store.visible.isEmpty && store.entries == [preset])
        store.undoRemoval(preset.id)
        #expect(store.visible == [preset])
        store.stageRemoval(preset.id)
        store.commitRemoval(preset.id)
        await writer.flush(deadline: .seconds(2))
        #expect(await state.load([RoomSavedView].self, from: .views).value == [])
    }

    @Test func presetSurvivesForgetHistoryAndNewerSchemaCannotBeEdited() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RoomStateStore(directory: directory)
        let future = RoomStateFile(name: RoomStateFile.views.name, schema: RoomStateFile.views.schema + 1,
                                   maxBytes: RoomStateFile.views.maxBytes, survivesForget: true)
        let preset = RoomSavedView(id: UUID(), name: "Keep me", root: root, nodePath: "", kind: nil, mode: .map)
        try await state.write([preset], to: future, generation: 1)
        _ = await state.forgetHistory()
        let store = RoomSavedViewsStore(writer: RoomStateWriter(store: state))
        await store.load()
        #expect(store.visible == [preset] && store.isReadOnly && !store.canAdd)
        #expect(!store.rename(preset.id, to: "Don’t change me"))
    }
}
