#if DEBUG
import AppKit
import Testing
@testable import RoomApp

@Suite("Native menu probe") @MainActor
struct RoomDebugMainMenuProbeTests {
    /// AppKit raises when a window that is not on screen is made main. Raised inside the probe's task, that exception
    /// is swallowed and leaves Swift's executor tracking dangling, so a later main-actor check crashes the app.
    @Test func makesTheWindowMainOnlyOnceItIsOnScreen() {
        let window = RoomMainWindowSpy()
        RoomDebugMainMenuProbe.bringForward(window)
        #expect(window.calls == ["orderFront", "makeMain"])
    }

    @Test func leavesAWindowThatCannotBecomeMainAlone() {
        let window = RoomMainWindowSpy()
        window.allowsMain = false
        RoomDebugMainMenuProbe.bringForward(window)
        #expect(window.calls == ["orderFront"])
    }
}

/// Records the calls instead of touching the screen.
private final class RoomMainWindowSpy: NSWindow {
    var calls: [String] = []
    var allowsMain = true
    override var canBecomeMain: Bool { allowsMain && calls.contains("orderFront") }
    override func makeKeyAndOrderFront(_ sender: Any?) { calls.append("orderFront") }
    override func makeMain() { calls.append("makeMain") }
}
#endif
