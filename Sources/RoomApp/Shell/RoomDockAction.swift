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
    /// What a running scan has counted, for Stop. Nil, or a total of zero, where the engine counts nothing.
    var progress: RoomDockProgress? = nil
    var perform: () -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.title == b.title && a.symbol == b.symbol && a.filled == b.filled && a.enabled == b.enabled
            && a.hint == b.hint && a.identifier == b.identifier && a.stamp == b.stamp && a.progress == b.progress
    }
}

/// Parts finished over parts asked. Only counted work is ever drawn as progress.
struct RoomDockProgress: Equatable, Sendable {
    let done: Int
    let total: Int
    var fraction: Double? { total > 0 ? Double(min(max(0, done), total)) / Double(total) : nil }
    var words: String? { total > 0 ? "\(min(max(0, done), total)) of \(total)" : nil }
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
