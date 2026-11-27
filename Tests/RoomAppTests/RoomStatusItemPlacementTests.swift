#if !ROOM_APP_STORE
import Foundation
import Testing
@testable import RoomApp

@Suite("Menu bar placement") @MainActor
struct RoomStatusItemPlacementTests {
    private let key = "NSStatusItem Preferred Position Item"

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "RoomStatusItemPlacementTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func aNewItemAsksForTheSpotByTheClock() throws {
        try withDefaults { defaults in
            RoomStatusItemPlacement.seed(name: "Item", defaults: defaults)
            #expect(defaults.object(forKey: key) as? Double == RoomStatusItemPlacement.byTheClock)
        }
    }

    @Test func aSavedPositionIsKept() throws {
        try withDefaults { defaults in
            defaults.set(412.0, forKey: key)
            RoomStatusItemPlacement.seed(name: "Item", defaults: defaults)
            #expect(defaults.double(forKey: key) == 412)
        }
    }

    /// Turning the item off removes its saved position; turning it back on must not move it again.
    @Test func itAsksOnlyOnce() throws {
        try withDefaults { defaults in
            RoomStatusItemPlacement.seed(name: "Item", defaults: defaults)
            defaults.removeObject(forKey: key)
            RoomStatusItemPlacement.seed(name: "Item", defaults: defaults)
            #expect(defaults.object(forKey: key) == nil)
        }
    }
}
#endif
