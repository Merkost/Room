import Testing
@testable import RoomApp

@MainActor
struct RoomDockActionTests {
    private func action(stamp: String = "", title: String = "Rescan", perform: @escaping () -> Void = {}) -> RoomDockAction {
        RoomDockAction(title: title, identifier: "id", stamp: stamp, perform: perform)
    }

    @Test func closuresDoNotMakeActionsDiffer() {
        #expect(action(perform: {}) == action(perform: { print("other") }))
        #expect(action(title: "Stop") != action())
    }

    @Test func aNewStampReplacesTheAction() {
        #expect(action(stamp: "a") != action(stamp: "a,b"))
    }

    @Test func progressIsDrawnOnlyWhenCounted() {
        #expect(RoomDockProgress(done: 3, total: 7).words == "3 of 7")
        #expect(RoomDockProgress(done: 9, total: 7).fraction == 1)
        #expect(RoomDockProgress(done: 0, total: 0).fraction == nil)
        #expect(RoomDockProgress(done: 0, total: 0).words == nil)
    }

    @Test func peekSaysWhatEachFigureMeans() {
        let input = RoomPlaceValue.Input(freeBytes: 64, capacityBytes: 494, cachesChecked: true, cachesReclaimableBytes: 22)
        let size: (Int64) -> String = { "\($0) GB" }
        #expect(RoomPlacePeek.sentence(.overview, input, size: size) == "64 GB free of 494 GB")
        #expect(RoomPlacePeek.sentence(.overview, input, belowGoal: true, size: size) == "64 GB free of 494 GB, under your goal")
        #expect(RoomPlacePeek.sentence(.clean, input, size: size) == "22 GB could go")
        #expect(RoomPlacePeek.sentence(.developer, input, size: size) == "Not scanned yet")
    }
}
