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
}
