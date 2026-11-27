import SwiftUI

/// One button in the dock's action slot, as the open screen describes it.
struct RoomDockAction: Equatable {
    var title: String
    var symbol: String? = nil
    /// Filled when it is the screen's real next step, plain otherwise.
    var filled = true
    var enabled = true
    var hint: String? = nil
    var identifier: String
    /// Whatever the closure captured by value (ticked rooms, a batch). A new stamp replaces the old closure.
    var stamp = ""
    var perform: () -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.title == b.title && a.symbol == b.symbol && a.filled == b.filled && a.enabled == b.enabled
            && a.hint == b.hint && a.identifier == b.identifier && a.stamp == b.stamp
    }
}

/// The screen's one main button and, at most, one small icon button beside it.
struct RoomDockActions: Equatable {
    var main: RoomDockAction?
    var side: RoomDockAction?
}

struct RoomDockActionKey: PreferenceKey {
    static var defaultValue: RoomDockActions? { nil }
    static func reduce(value: inout RoomDockActions?, nextValue: () -> RoomDockActions?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Puts this screen's next step in the dock.
    func roomDock(_ main: RoomDockAction?, side: RoomDockAction? = nil) -> some View {
        preference(key: RoomDockActionKey.self, value: RoomDockActions(main: main, side: side))
    }
}
