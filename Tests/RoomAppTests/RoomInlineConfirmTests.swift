import Foundation
import Testing
@testable import RoomApp

struct RoomInlineConfirmTests {
    let start = Date(timeIntervalSince1970: 1_600_000_000)

    @Test func removeAccessCommitsAfter8s() {
        var confirm = RoomInlineConfirm()
        let armed = confirm.press(at: start)
        let staged = confirm.press(at: start.addingTimeInterval(1))
        let early = confirm.tick(at: start.addingTimeInterval(8))
        let due = confirm.tick(at: start.addingTimeInterval(9))
        #expect(armed == .arm && staged == .stage && early == .none && due == .commit)
    }

    @Test func expiredArmMustBePressedAgain() {
        var confirm = RoomInlineConfirm()
        _ = confirm.press(at: start)
        let expired = confirm.press(at: start.addingTimeInterval(4))
        #expect(expired == .arm)
        let escaped = confirm.escape()
        #expect(escaped == .disarm && confirm.phase == .idle)
    }

    @Test func undoRestoresApprovalWhenStaged() {
        var confirm = RoomInlineConfirm()
        _ = confirm.press(at: start)
        _ = confirm.press(at: start.addingTimeInterval(1))
        let undone = confirm.undoPressed(at: start.addingTimeInterval(8))
        let closed = confirm.flush()
        #expect(undone == .undo && closed == .none)
    }

    @Test func quitCommitsStaged() {
        var confirm = RoomInlineConfirm()
        _ = confirm.press(at: start)
        _ = confirm.press(at: start.addingTimeInterval(1))
        let quit = confirm.flush()
        #expect(quit == .commit && confirm.phase == .idle)
    }

    @MainActor @Test func forgetHistoryDiscardsPendingWritesAndKeepsRooms() async throws {
        let directory = try reserveStateFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomStateStore(directory: directory)
        let writer = RoomStateWriter(store: store, debounce: .seconds(60))
        try await store.write(["old"], to: .roomSizes, generation: 0)
        writer.submit(["pending sizes"], to: .roomSizes)
        writer.submit(["kept room"], to: .rooms)
        writer.forgetHistory { names in #expect(names.contains(RoomStateFile.roomSizes.name)) }
        writer.submit(["during forget"], to: .roomSizes)
        await writer.flush(deadline: .seconds(4))
        #expect(await store.load([String].self, from: .roomSizes).value == nil)
        #expect(await store.load([String].self, from: .rooms).value == ["kept room"])
        writer.submit(["new measurement"], to: .roomSizes)
        await writer.flush(deadline: .seconds(4))
        #expect(await store.load([String].self, from: .roomSizes).value == ["new measurement"])
    }
}
