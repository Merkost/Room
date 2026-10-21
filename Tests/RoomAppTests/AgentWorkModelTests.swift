#if !ROOM_APP_STORE
import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Worktree UI authorization boundaries") @MainActor
struct AgentWorkModelTests {
    @Test("A verified-looking row cannot move a checkout without native review grants")
    func unreviewedMoveIsRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Room-UI-Work-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("keep.txt")
        try Data("unchanged".utf8).write(to: sentinel)
        let engine = AgentWorkEngine(homeDirectory: root, activityDirectory: root.appendingPathComponent("receipts"))
        let model = AgentWorkModel(engine: engine)
        let item = AgentWorkItem(id: root.path, url: root, title: "Owned fixture", owner: .project,
            repositoryURL: nil, gitAdminURL: nil, gitCommonURL: nil, branch: "main", head: String(repeating: "a", count: 40),
            lastActivityAt: .distantPast, allocatedBytes: 4096, isPartial: false, changedCount: 0, untrackedCount: 0,
            ignoredCount: 0, processIDs: [], isLinkedWorktree: true, isLocked: false, isPrunable: false,
            heldReasons: [], pushVerification: AgentWorkPushVerification(state: .verified, checkedAt: Date(),
                head: String(repeating: "a", count: 40), remoteName: "origin", detail: "Fixture"))
        #expect(!model.allLocationsGranted)
        #expect(await model.moveToTrash(item, confirmsFinished: true) == false)
        #expect(try Data(contentsOf: sentinel) == Data("unchanged".utf8))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("receipts").path))
        #expect(model.receipts.isEmpty)
    }

    @Test("Stop without an operation never starts inspection or mutates files")
    func idleLifecycleIsInert() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Room-UI-Lifecycle-" + UUID().uuidString, isDirectory: true)
        let model = AgentWorkModel(engine: AgentWorkEngine(homeDirectory: root))
        model.stop()
        #expect(!model.isWorking && !model.isScanning)
        #expect(model.report == nil && model.verifyingID == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

#endif
