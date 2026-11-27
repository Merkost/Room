#if !ROOM_APP_STORE
import Foundation

/// Asks macOS to put a new menu bar item next to the system items instead of at the far left, where a notch can hide it.
///
/// There is no public API for this: `NSStatusItem Preferred Position <autosaveName>` is where AppKit remembers an
/// item's distance from the right edge. It is undocumented and may stop working, so it stays out of the Store edition.
/// It is written once per install and never over a position that is already saved.
enum RoomStatusItemPlacement {
    static let byTheClock: Double = 1

    static func seed(name: String, defaults: UserDefaults = .standard) {
        let asked = "RoomStatusItemPlaced \(name)"
        guard !defaults.bool(forKey: asked) else { return }
        defaults.set(true, forKey: asked)
        let position = "NSStatusItem Preferred Position \(name)"
        guard defaults.object(forKey: position) == nil else { return }
        defaults.set(byTheClock, forKey: position)
    }
}
#endif
