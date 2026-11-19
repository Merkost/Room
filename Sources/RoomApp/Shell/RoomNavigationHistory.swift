import Foundation

/// Go › Back / Forward (⌘[ / ⌘]). In memory per window, like a browser's history; never persisted (D-FND-3).
nonisolated struct RoomNavigationHistory: Equatable, Sendable {
    static let limit = 50
    private(set) var back: [RoomRoute] = []
    private(set) var forward: [RoomRoute] = []
    private(set) var current: RoomRoute

    init(current: RoomRoute) { self.current = current }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// A new selection: the old place goes on the back stack and the forward stack is cleared. Re-selecting is a no-op.
    mutating func visit(_ route: RoomRoute) {
        guard route != current else { return }
        back.append(current)
        if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
        forward.removeAll()
        current = route
    }
    @discardableResult mutating func goBack() -> RoomRoute? {
        guard let previous = back.popLast() else { return nil }
        forward.append(current); current = previous; return previous
    }
    @discardableResult mutating func goForward() -> RoomRoute? {
        guard let next = forward.popLast() else { return nil }
        back.append(current); current = next; return next
    }
    /// A Room was unpinned or a view deleted: its entries leave both stacks (never navigate to a dead route).
    mutating func remove(_ route: RoomRoute, fallback: RoomRoute) {
        back.removeAll { $0 == route }
        forward.removeAll { $0 == route }
        if current == route { current = fallback }
        // Collapse neighbours that became equal, and drop a back top equal to current.
        back = back.reduce(into: []) { out, r in if out.last != r { out.append(r) } }
        while back.last == current { back.removeLast() }
        while forward.last == current { forward.removeLast() }
    }
}
